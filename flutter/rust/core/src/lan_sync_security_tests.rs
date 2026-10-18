use super::*;

fn service() -> Service {
    let service = Service::new(Arc::new(Mutex::new(
        storage::open(std::path::Path::new(":memory:")).unwrap(),
    )))
    .unwrap();
    service.active.store(true, Ordering::SeqCst);
    service
}
fn listen(service: &Service) -> (SocketAddr, std::thread::JoinHandle<Result<(), String>>) {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let address = listener.local_addr().unwrap();
    let service = service.clone();
    let worker = std::thread::spawn(move || {
        let (socket, address) = listener.accept().unwrap();
        service.receive(socket, address)
    });
    (address, worker)
}
fn invite(service: &Service) -> Peer {
    service.invitation(Ipv4Addr::LOCALHOST.to_string()).unwrap();
    let invitation = lock(&service.runtime)
        .unwrap()
        .pending
        .as_ref()
        .unwrap()
        .invite
        .clone();
    Peer {
        id: invitation.id,
        name: invitation.name,
        address: invitation.address,
        pair: invitation.pair,
        key: invitation.key,
        last_sync: None,
        acknowledged: None,
    }
}
fn pair(a: &Service, b: &Service) -> Peer {
    let invitation = invite(b);
    let (address, worker) = listen(b);
    a.pair_at(invitation.clone(), address).unwrap();
    worker.join().unwrap().unwrap();
    invitation
}
fn identify(socket: &mut TcpStream, pair: &str, pairing: bool) {
    negotiate(socket, true).unwrap();
    write_frame(
        socket,
        &serde_json::to_vec(&Identification {
            pair: pair.into(),
            pairing,
        })
        .unwrap(),
    )
    .unwrap();
}
fn pairing_proxy(target: SocketAddr, cut: usize) -> (SocketAddr, std::thread::JoinHandle<()>) {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let address = listener.local_addr().unwrap();
    let worker = std::thread::spawn(move || {
        let (mut client, _) = listener.accept().unwrap();
        let mut server = TcpStream::connect(target).unwrap();
        // Public greeting, identification/Noise, identity, offer, prepared,
        // stored, fresh-key Noise and both final identities. Transport messages
        // each contain a payload frame followed by an authenticated terminator.
        for (step, (outbound, frames)) in [
            (true, 1),
            (false, 1),
            (true, 2),
            (false, 1),
            (true, 2),
            (false, 2),
            (true, 2),
            (false, 2),
            (true, 1),
            (false, 1),
            (true, 2),
            (false, 2),
        ]
        .into_iter()
        .enumerate()
        {
            let (from, to) = if outbound {
                (&mut client, &mut server)
            } else {
                (&mut server, &mut client)
            };
            for _ in 0..frames {
                let frame = read_frame(from, 65535).unwrap();
                if step != cut {
                    write_frame(to, &frame).unwrap();
                }
            }
            if step == cut {
                return;
            }
        }
    });
    (address, worker)
}
fn recipe_rows(service: &Service) -> Vec<(String, String)> {
    let db = lock(&service.db).unwrap();
    let mut result = Vec::new();
    for table in ["recipes", "history", "heads", "state"] {
        let mut statement = db
            .prepare(&format!("SELECT * FROM {table} ORDER BY 1"))
            .unwrap();
        let count = statement.column_count();
        let rows = statement
            .query_map([], |r| {
                Ok((
                    table.to_string(),
                    (0..count)
                        .map(|i| format!("{:?}", r.get_ref(i).unwrap()))
                        .collect::<Vec<_>>()
                        .join("|"),
                ))
            })
            .unwrap();
        result.extend(rows.map(Result::unwrap));
    }
    result
}
fn seed(service: &Service) {
    let book: storage::Book =
        serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap();
    storage::save(&mut lock(&service.db).unwrap(), 0, &book, "synthetic").unwrap();
}

#[test]
fn invitation_secret_cannot_authenticate_either_direction_before_or_after_expiry() {
    let (a, b) = (service(), service());
    seed(&a);
    let before_a = recipe_rows(&a);
    let before_b = recipe_rows(&b);
    let invitation = pair(&a, &b);
    assert_eq!(recipe_rows(&a), before_a);
    assert_eq!(recipe_rows(&b), before_b);
    let peer_a = lock(&a.runtime).unwrap().config.peers[0].clone();
    let peer_b = lock(&b.runtime).unwrap().config.peers[0].clone();
    assert_ne!(peer_a.key, invitation.key);
    assert_ne!(peer_a.pair, invitation.pair);
    assert_eq!(peer_a.key, peer_b.key);
    assert!(
        !serde_json::to_string(&lock(&a.runtime).unwrap().config)
            .unwrap()
            .contains(&invitation.key)
    );
    assert!(
        !serde_json::to_string(&lock(&b.runtime).unwrap().config)
            .unwrap()
            .contains(&invitation.key)
    );
    // The invitation expires/gets discarded on claim; no clock-based path can
    // resurrect it. Exercise both logical times and both permanent identifiers.
    for expired in [false, true] {
        if expired {
            assert!(lock(&b.runtime).unwrap().pending.is_none());
        }
        for (target, peer) in [(&a, &peer_a), (&b, &peer_b)] {
            let (address, worker) = listen(target);
            let mut socket = TcpStream::connect(address).unwrap();
            identify(&mut socket, &peer.pair, false);
            assert!(handshake(&mut socket, &key(&invitation.key).unwrap(), true).is_err());
            assert!(worker.join().unwrap().is_err());
            assert!(!target.status().unwrap().to_string().contains(&peer.key));
        }
    }
    let (address, worker) = listen(&b);
    a.exchange_at(peer_a, address, true).unwrap();
    worker.join().unwrap().unwrap();
    assert_eq!(
        storage::load(&mut lock(&a.db).unwrap())
            .unwrap()
            .book
            .recipes,
        storage::load(&mut lock(&b.db).unwrap())
            .unwrap()
            .book
            .recipes
    );
    assert!(lock(&a.runtime).unwrap().config.staged.is_empty());
    assert!(lock(&b.runtime).unwrap().config.staged.is_empty());
}

#[test]
fn invitations_are_single_attempt_single_device_and_expire_unused() {
    let (a, b, c) = (service(), service(), service());
    let invitation = pair(&a, &b);
    for client in [&a, &c] {
        let (address, worker) = listen(&b);
        assert!(client.pair_at(invitation.clone(), address).is_err());
        assert!(worker.join().unwrap().is_err());
    }
    let invitation = invite(&b);
    lock(&b.runtime).unwrap().pending.as_mut().unwrap().expires =
        Instant::now() - Duration::from_secs(1);
    let (address, worker) = listen(&b);
    assert!(c.pair_at(invitation, address).is_err());
    assert!(worker.join().unwrap().is_err());
    assert!(lock(&c.runtime).unwrap().config.peers.is_empty());
}

#[test]
fn interrupted_pairing_never_changes_recipes_and_fresh_invitation_recovers() {
    for phase in 0..5 {
        let (a, b) = (service(), service());
        seed(&b);
        let before = recipe_rows(&b);
        let invitation = invite(&b);
        let (address, worker) = listen(&b);
        let mut socket = TcpStream::connect(address).unwrap();
        identify(&mut socket, &invitation.pair, true);
        if phase > 0 {
            let mut noise = handshake(&mut socket, &key(&invitation.key).unwrap(), true).unwrap();
            if phase > 1 {
                send(&mut socket, &mut noise, &a.identity().unwrap()).unwrap();
                let offer: Offer = recv_small(&mut socket, &mut noise).unwrap();
                if phase > 2 {
                    send(&mut socket, &mut noise, &Receipt { version: VERSION }).unwrap();
                    check_receipt(recv_small(&mut socket, &mut noise).unwrap()).unwrap();
                    if phase > 3 {
                        let _ = handshake(&mut socket, &key(&offer.key).unwrap(), true).unwrap();
                    }
                }
            }
        }
        drop(socket);
        assert!(worker.join().unwrap().is_err());
        assert!(lock(&b.runtime).unwrap().config.peers.is_empty());
        // Only a hidden fresh-key recovery record may remain before confirmation.
        assert_eq!(recipe_rows(&b), before);
        pair(&a, &b);
        assert_eq!(lock(&a.runtime).unwrap().config.peers.len(), 1);
        assert_eq!(lock(&b.runtime).unwrap().config.peers.len(), 1);
        assert_eq!(recipe_rows(&b), before);
    }
}

#[test]
fn completed_pairing_survives_restart_new_invitations_and_blocked_recipe_sync() {
    let (a, b) = (service(), service());
    pair(&a, &b);
    let peer = lock(&a.runtime).unwrap().config.peers[0].clone();
    assert!(lock(&a.runtime).unwrap().config.staged.is_empty());
    assert!(lock(&b.runtime).unwrap().config.staged.is_empty());
    let reopened = Service::new(a.db.clone()).unwrap();
    reopened.active.store(true, Ordering::SeqCst);
    // Creating another invitation and a failed recipe export must preserve trust.
    invite(&b);
    lock(&reopened.db)
        .unwrap()
        .execute("INSERT INTO recipes VALUES('broken','{}','broken')", [])
        .unwrap();
    let (address, worker) = listen(&b);
    assert!(reopened.exchange_at(peer.clone(), address, true).is_err());
    assert!(worker.join().unwrap().is_err());
    assert_eq!(
        lock(&reopened.runtime).unwrap().config.peers[0].key,
        peer.key
    );
    assert_eq!(lock(&b.runtime).unwrap().config.peers[0].key, peer.key);
    assert_eq!(
        Service::new(b.db.clone()).unwrap().status().unwrap()["peers"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn real_final_confirmation_loss_recovers_after_restart_without_invitation_or_recipe_changes() {
    let (a, b) = (service(), service());
    seed(&a);
    let before_a = recipe_rows(&a);
    let before_b = recipe_rows(&b);
    let invitation = invite(&b);
    let (target, server) = listen(&b);
    let (address, proxy) = pairing_proxy(target, 11);
    assert!(a.pair_at(invitation, address).is_err());
    proxy.join().unwrap();
    server.join().unwrap().unwrap();
    assert!(lock(&a.runtime).unwrap().config.peers.is_empty());
    assert_eq!(lock(&b.runtime).unwrap().config.peers.len(), 1);
    assert_eq!(recipe_rows(&a), before_a);
    assert_eq!(recipe_rows(&b), before_b);
    let reopened = Service::new(a.db.clone()).unwrap();
    reopened.active.store(true, Ordering::SeqCst);
    let peer = lock(&reopened.runtime).unwrap().config.staged[0]
        .peer
        .clone();
    assert_eq!(peer.key, lock(&b.runtime).unwrap().config.peers[0].key);
    let (target, server) = listen(&b);
    reopened.exchange_at(peer, target, true).unwrap();
    server.join().unwrap().unwrap();
    assert_eq!(lock(&reopened.runtime).unwrap().config.peers.len(), 1);
    assert!(lock(&reopened.runtime).unwrap().config.staged.is_empty());
}

#[test]
fn drop_before_remote_prepare_leaves_only_hidden_journal_and_new_invitation_replaces_it() {
    let (a, b) = (service(), service());
    let invitation = invite(&b);
    let (target, server) = listen(&b);
    let (address, proxy) = pairing_proxy(target, 6);
    assert!(a.pair_at(invitation, address).is_err());
    proxy.join().unwrap();
    assert!(server.join().unwrap().is_err());
    assert!(lock(&a.runtime).unwrap().config.peers.is_empty());
    assert!(lock(&b.runtime).unwrap().config.peers.is_empty());
    assert_eq!(lock(&a.runtime).unwrap().config.staged.len(), 1);
    assert!(lock(&b.runtime).unwrap().config.staged.is_empty());
    pair(&a, &b);
    assert!(lock(&a.runtime).unwrap().config.staged.is_empty());
    assert!(lock(&b.runtime).unwrap().config.staged.is_empty());
    assert_eq!(lock(&a.runtime).unwrap().config.peers.len(), 1);
    assert_eq!(lock(&b.runtime).unwrap().config.peers.len(), 1);
}

#[test]
fn forget_before_preparation_or_confirmation_cannot_be_undone() {
    let (a, b) = (service(), service());
    let peer = invite(&b);
    let epoch = lock(&a.runtime).unwrap().pairing_epoch;
    a.forget(&peer.id).unwrap();
    assert!(a.stage_peer(peer.clone(), epoch).is_err());
    let epoch = lock(&a.runtime).unwrap().pairing_epoch;
    a.stage_peer(peer.clone(), epoch).unwrap();
    a.forget(&peer.id).unwrap();
    assert!(a.confirm_peer(&peer, Some(epoch)).is_err());
    assert!(lock(&a.runtime).unwrap().config.peers.is_empty());
    assert!(lock(&a.runtime).unwrap().config.staged.is_empty());
    // Address fallback must retain the original epoch, even after availability
    // resumes; revocation is checked before opening the next target socket.
    let unavailable = SocketAddr::from((Ipv4Addr::LOCALHOST, PORT));
    assert!(
        a.pair_at_epoch(peer, unavailable, epoch)
            .unwrap_err()
            .contains("revoked")
    );
}

#[test]
fn full_peer_list_allows_authenticated_replacement_but_not_a_seventeenth_identity() {
    let (a, b, c) = (service(), service(), service());
    {
        let mut rt = lock(&b.runtime).unwrap();
        for i in 0..15 {
            rt.config.peers.push(Peer {
                id: format!("fixture-{i}"),
                name: format!("Fixture {i}"),
                address: SocketAddr::from((Ipv4Addr::LOCALHOST, PORT)).to_string(),
                pair: Uuid::new_v4().to_string(),
                key: B64.encode([i; 32]),
                last_sync: None,
                acknowledged: None,
            });
        }
    }
    pair(&a, &b);
    assert_eq!(lock(&b.runtime).unwrap().config.peers.len(), 16);
    let first_key = lock(&a.runtime).unwrap().config.peers[0].key.clone();
    pair(&a, &b);
    assert_eq!(lock(&b.runtime).unwrap().config.peers.len(), 16);
    assert_ne!(lock(&a.runtime).unwrap().config.peers[0].key, first_key);
    let invitation = invite(&b);
    let (address, server) = listen(&b);
    assert!(c.pair_at(invitation, address).is_err());
    assert!(server.join().unwrap().unwrap_err().contains("16"));
    assert_eq!(lock(&b.runtime).unwrap().config.peers.len(), 16);
    let status = c.status().unwrap();
    assert_eq!(status["peers"][0]["pairingPending"], true);
    assert_eq!(status["peers"][0]["caughtUp"], false);
    c.forget(&b.id).unwrap();
    assert!(c.status().unwrap()["peers"].as_array().unwrap().is_empty());
}

#[test]
fn protocol_gate_rejects_before_key_lookup_and_backs_off() {
    let b = service();
    seed(&b);
    let before = recipe_rows(&b);
    let invitation = invite(&b);
    lock(&b.runtime)
        .unwrap()
        .pending
        .as_mut()
        .unwrap()
        .invite
        .key = "not-a-key".into();
    for version in [3, 5] {
        let (address, worker) = listen(&b);
        let mut socket = TcpStream::connect(address).unwrap();
        write_frame(&mut socket, format!("cookdex-sync/{version}").as_bytes()).unwrap();
        assert_eq!(read_frame(&mut socket, 128).unwrap(), b"cookdex-sync/4");
        assert_eq!(
            worker.join().unwrap().unwrap_err(),
            version_message(version)
        );
        assert_eq!(recipe_rows(&b), before);
        assert_eq!(
            lock(&b.runtime)
                .unwrap()
                .pending
                .as_ref()
                .unwrap()
                .invite
                .pair,
            invitation.pair
        );
    }
    let a = service();
    let mut rt = lock(&a.runtime).unwrap();
    let at = Instant::now();
    rt.record_result("peer", &Err(VERSION_ERROR.into()), at);
    assert_eq!(rt.retry_after("peer", false, at), Some(60));
    assert_eq!(rt.retry_after("peer", true, at), None);
}

#[test]
fn protocol_three_wire_refuses_new_hello_without_using_old_key() {
    let a = service();
    let peer = Peer {
        id: "old-peer".into(),
        name: "Old device".into(),
        address: String::new(),
        pair: Uuid::new_v4().to_string(),
        key: "invalid-key-proves-gate-first".into(),
        last_sync: None,
        acknowledged: None,
    };
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let address = listener.local_addr().unwrap();
    let old_pair = peer.pair.clone();
    let worker = std::thread::spawn(move || {
        let (mut socket, _) = listener.accept().unwrap();
        // Exact v3 first operation: parse a framed pairing identifier, look up
        // known/pending ID, then refuse an unknown value without any Noise call.
        let pair = String::from_utf8(read_frame(&mut socket, 128).unwrap()).unwrap();
        assert_ne!(pair, old_pair);
        assert_eq!(pair, "cookdex-sync/4");
    });
    assert_eq!(
        a.exchange_at(peer, address, false).unwrap_err(),
        VERSION_ERROR
    );
    worker.join().unwrap();
    assert_eq!(recipe_rows(&a).len(), 1);
}

#[test]
fn upgrade_atomically_clears_only_old_pairings_and_notice_dismissal_persists() {
    let a = service();
    seed(&a);
    let before = recipe_rows(&a);
    let old = json!({"enabled":true,"name":"Test device","peers":[{"id":"legacy","name":"Legacy device","address":"fixture","pair":"legacy-pair","key":"legacy-secret"}]});
    {
        let db = lock(&a.db).unwrap();
        storage::put_local(&db, "syncConfig", &old).unwrap();
        storage::put_local(&db, "other-setting", &json!({"keep":true})).unwrap();
        db.execute_batch("CREATE TRIGGER fail_sync_migration BEFORE UPDATE ON local WHEN NEW.key='syncConfig' BEGIN SELECT RAISE(ABORT,'test failure'); END;").unwrap();
    }
    assert!(Service::new(a.db.clone()).is_err());
    assert_eq!(
        storage::local(&lock(&a.db).unwrap(), "syncConfig").unwrap(),
        Some(old)
    );
    assert_eq!(recipe_rows(&a), before);
    lock(&a.db)
        .unwrap()
        .execute_batch("DROP TRIGGER fail_sync_migration")
        .unwrap();
    let updated = Service::new(a.db.clone()).unwrap();
    assert!(
        updated.status().unwrap()["peers"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert_eq!(updated.status().unwrap()["rePairRequired"], true);
    assert_eq!(updated.status().unwrap()["name"], "Test device");
    assert_eq!(updated.status().unwrap()["enabled"], true);
    assert_eq!(recipe_rows(&updated), before);
    assert_eq!(
        storage::local(&lock(&a.db).unwrap(), "other-setting").unwrap(),
        Some(json!({"keep":true}))
    );
    updated.dismiss_pairing_notice().unwrap();
    assert_eq!(
        Service::new(a.db.clone()).unwrap().status().unwrap()["rePairRequired"],
        false
    );
    assert_eq!(recipe_rows(&updated), before);
}

#[test]
fn slowly_dripped_identification_cannot_restart_absolute_deadline() {
    let b = service();
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let address = listener.local_addr().unwrap();
    let worker = std::thread::spawn(move || {
        let (socket, address) = listener.accept().unwrap();
        let start = Instant::now();
        let error = b
            .receive_admitted(socket, address, start + Duration::from_millis(250), None)
            .unwrap_err();
        (start.elapsed(), error)
    });
    let mut socket = TcpStream::connect(address).unwrap();
    for byte in [0, 0, 0, 128]
        .into_iter()
        .chain(std::iter::repeat_n(b'x', 100))
    {
        if socket.write_all(&[byte]).is_err() {
            break;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    let (elapsed, _) = worker.join().unwrap();
    assert!(elapsed >= Duration::from_millis(250));
    assert!(elapsed < Duration::from_secs(1), "{elapsed:?}");
}

#[test]
fn pairing_payload_after_noise_uses_the_same_absolute_deadline() {
    let (a, b) = (service(), service());
    let invitation = invite(&b);
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let address = listener.local_addr().unwrap();
    let server = b.clone();
    let worker = std::thread::spawn(move || {
        let (socket, address) = listener.accept().unwrap();
        let start = Instant::now();
        let result =
            server.receive_admitted(socket, address, start + Duration::from_millis(400), None);
        (start.elapsed(), result)
    });
    let mut socket = TcpStream::connect(address).unwrap();
    identify(&mut socket, &invitation.pair, true);
    let mut noise = handshake(&mut socket, &key(&invitation.key).unwrap(), true).unwrap();
    let mut cipher = [0; 4096];
    let n = noise
        .write_message(
            &serde_json::to_vec(&a.identity().unwrap()).unwrap(),
            &mut cipher,
        )
        .unwrap();
    let bytes = (n as u32)
        .to_be_bytes()
        .into_iter()
        .chain(cipher[..n].iter().copied());
    for byte in bytes {
        if socket.write_all(&[byte]).is_err() {
            break;
        }
        std::thread::sleep(Duration::from_millis(15));
    }
    let (elapsed, result) = worker.join().unwrap();
    assert!(result.is_err());
    assert!(elapsed >= Duration::from_millis(400));
    assert!(elapsed < Duration::from_secs(1));
    assert!(lock(&b.runtime).unwrap().config.peers.is_empty());
    assert!(lock(&b.runtime).unwrap().config.staged.is_empty());
}

#[test]
fn source_limit_cooldown_and_authenticated_release_allow_other_sources_and_retry() {
    let mut admission = Admission::default();
    let first = IpAddr::V4(Ipv4Addr::LOCALHOST);
    let second = IpAddr::V4(Ipv4Addr::new(127, 0, 0, 2));
    let at = Instant::now();
    assert!(admission.acquire(first, at));
    assert!(!admission.acquire(first, at));
    assert!(admission.acquire(second, at));
    admission.release(second, false, at);
    assert!(admission.acquire(second, at));
    admission.release(first, true, at);
    assert!(!admission.acquire(first, at + Duration::from_secs(1)));
    assert!(admission.acquire(first, at + COOLDOWN));
    assert_eq!(admission.sources.len(), 2);
}

#[test]
fn pairing_and_sync_work_while_another_source_holds_an_incoming_connection() {
    let (a, b) = (service(), service());
    seed(&a);
    let held_source = IpAddr::V4(Ipv4Addr::new(127, 0, 0, 2));
    let accepted = Instant::now();
    assert!(lock(&b.admission).unwrap().acquire(held_source, accepted));
    b.inbound.store(1, Ordering::SeqCst);
    let permit = AdmissionGuard {
        admission: b.admission.clone(),
        ip: held_source,
        authenticated: false,
    };
    let held_listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let held_address = held_listener.local_addr().unwrap();
    let holder = TcpStream::connect(held_address).unwrap();
    let (held_socket, _) = held_listener.accept().unwrap();
    let server = b.clone();
    let held_worker = std::thread::spawn(move || {
        // Inject the accepted source identity so this portable loopback fixture
        // can model two LAN sources without a platform-specific bind API.
        server.receive_admitted(
            held_socket,
            SocketAddr::new(held_source, PORT),
            accepted + AUTH_TIMEOUT,
            Some(permit),
        )
    });
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let address = listener.local_addr().unwrap();
    b.listener_port.store(address.port(), Ordering::SeqCst);
    let server = b.clone();
    lock(&b.workers)
        .unwrap()
        .push(std::thread::spawn(move || server.listen(listener)));
    let invitation = invite(&b);
    a.pair_at(invitation, address).unwrap();
    let peer = lock(&a.runtime).unwrap().config.peers[0].clone();
    a.exchange_at(peer, address, true).unwrap();
    assert_eq!(
        storage::load(&mut lock(&b.db).unwrap())
            .unwrap()
            .book
            .recipes
            .len(),
        storage::load(&mut lock(&a.db).unwrap())
            .unwrap()
            .book
            .recipes
            .len()
    );
    assert!(
        lock(&b.admission)
            .unwrap()
            .sources
            .get(&held_source)
            .unwrap()
            .busy
    );
    drop(holder);
    assert!(held_worker.join().unwrap().is_err());
    b.inbound.fetch_sub(1, Ordering::SeqCst);
    b.shutdown();
}

#[test]
fn old_client_is_refused_before_any_noise_key_is_selected() {
    let b = service();
    let invitation = invite(&b);
    let (address, worker) = listen(&b);
    let mut old = TcpStream::connect(address).unwrap();
    // v3 writes pairing ID first and expects a Noise reply. v4 responds with a
    // public version marker, then closes. v3's Snow decoder returns an error.
    write_frame(&mut old, invitation.pair.as_bytes()).unwrap();
    assert_eq!(read_frame(&mut old, 128).unwrap(), b"cookdex-sync/4");
    assert_eq!(worker.join().unwrap().unwrap_err(), VERSION_ERROR);
    assert!(lock(&b.runtime).unwrap().pending.is_some());
    assert!(lock(&b.runtime).unwrap().config.peers.is_empty());
}
