# Dependency licenses

Inventory of locked Rust and Dart packages (including test/code-generation and non-shipping platform packages), the resolved Android release runtime graph, host-test/build plugin roots, and native/assets dependencies. Package license files and Maven POM metadata are the evidence. Dependencies are downloaded from upstream; they are not vendored in this source export. MIT applies to cookdex itself, not to third-party components.

**Flagged licenses:** JUnit 4.13.2 is EPL-1.0 copyleft and used only by host tests, not production packages. `r-efi` offers LGPL-2.1-or-later alongside MIT/Apache-2.0; the MIT option is selected for the reviewed versions listed below. Zint includes GPL frontend/Qt code in its upstream distribution, but ZXing compiles only its BSD backend. No unresolved copyleft or unknown license flags remain in this inventory. Keep upstream attribution and notices when redistributing binaries. Flutter supplies its bundled license notices; inspect native component notices as well.

Developer tools and platform SDKs have their own licenses and redistribution terms (including Microsoft runtime terms). They are installed separately. Build-plugin transitive tooling is not a complete legal inventory of the SDK installations. This list describes the app dependency closure and the explicitly listed development roots.

| Ecosystem | Package | Version | License / notice |
|---|---|---|---|
| Android | [androidx.activity:activity](https://maven.google.com/web/index.html#androidx.activity:activity:1.13.0) | 1.13.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.annotation:annotation](https://maven.google.com/web/index.html#androidx.annotation:annotation:1.10.0) | 1.10.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.annotation:annotation-experimental](https://maven.google.com/web/index.html#androidx.annotation:annotation-experimental:1.4.1) | 1.4.1 | The Apache Software License, Version 2.0 |
| Android | [androidx.annotation:annotation-jvm](https://maven.google.com/web/index.html#androidx.annotation:annotation-jvm:1.10.0) | 1.10.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.arch.core:core-common](https://maven.google.com/web/index.html#androidx.arch.core:core-common:2.2.0) | 2.2.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.arch.core:core-runtime](https://maven.google.com/web/index.html#androidx.arch.core:core-runtime:2.2.0) | 2.2.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.camera.featurecombinationquery:featurecombinationquery](https://maven.google.com/web/index.html#androidx.camera.featurecombinationquery:featurecombinationquery:1.6.2) | 1.6.2 | The Apache Software License, Version 2.0 |
| Android | [androidx.camera:camera-camera2](https://maven.google.com/web/index.html#androidx.camera:camera-camera2:1.6.2) | 1.6.2 | The Apache Software License, Version 2.0 |
| Android | [androidx.camera:camera-camera2-pipe](https://maven.google.com/web/index.html#androidx.camera:camera-camera2-pipe:1.6.2) | 1.6.2 | The Apache Software License, Version 2.0 |
| Android | [androidx.camera:camera-core](https://maven.google.com/web/index.html#androidx.camera:camera-core:1.6.2) | 1.6.2 | The Apache Software License, Version 2.0 OR BSD-3-Clause |
| Android | [androidx.camera:camera-lifecycle](https://maven.google.com/web/index.html#androidx.camera:camera-lifecycle:1.6.2) | 1.6.2 | The Apache Software License, Version 2.0 |
| Android | [androidx.camera:camera-video](https://maven.google.com/web/index.html#androidx.camera:camera-video:1.6.2) | 1.6.2 | The Apache Software License, Version 2.0 |
| Android | [androidx.collection:collection](https://maven.google.com/web/index.html#androidx.collection:collection:1.4.2) | 1.4.2 | The Apache Software License, Version 2.0 |
| Android | [androidx.collection:collection-jvm](https://maven.google.com/web/index.html#androidx.collection:collection-jvm:1.4.2) | 1.4.2 | The Apache Software License, Version 2.0 |
| Android | [androidx.compose.runtime:runtime-annotation](https://maven.google.com/web/index.html#androidx.compose.runtime:runtime-annotation:1.9.0) | 1.9.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.compose.runtime:runtime-annotation-android](https://maven.google.com/web/index.html#androidx.compose.runtime:runtime-annotation-android:1.9.0) | 1.9.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.concurrent:concurrent-futures](https://maven.google.com/web/index.html#androidx.concurrent:concurrent-futures:1.1.0) | 1.1.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.concurrent:concurrent-futures-ktx](https://maven.google.com/web/index.html#androidx.concurrent:concurrent-futures-ktx:1.1.0) | 1.1.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.core:core](https://maven.google.com/web/index.html#androidx.core:core:1.18.0) | 1.18.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.core:core-backported-fixes](https://maven.google.com/web/index.html#androidx.core:core-backported-fixes:1.0.0) | 1.0.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.core:core-ktx](https://maven.google.com/web/index.html#androidx.core:core-ktx:1.18.0) | 1.18.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.core:core-viewtree](https://maven.google.com/web/index.html#androidx.core:core-viewtree:1.0.0) | 1.0.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.customview:customview](https://maven.google.com/web/index.html#androidx.customview:customview:1.0.0) | 1.0.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.exifinterface:exifinterface](https://maven.google.com/web/index.html#androidx.exifinterface:exifinterface:1.4.2) | 1.4.2 | The Apache Software License, Version 2.0 |
| Android | [androidx.fragment:fragment](https://maven.google.com/web/index.html#androidx.fragment:fragment:1.7.1) | 1.7.1 | The Apache Software License, Version 2.0 |
| Android | [androidx.interpolator:interpolator](https://maven.google.com/web/index.html#androidx.interpolator:interpolator:1.0.0) | 1.0.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.lifecycle:lifecycle-common](https://maven.google.com/web/index.html#androidx.lifecycle:lifecycle-common:2.7.0) | 2.7.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.lifecycle:lifecycle-common-java8](https://maven.google.com/web/index.html#androidx.lifecycle:lifecycle-common-java8:2.7.0) | 2.7.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.lifecycle:lifecycle-livedata](https://maven.google.com/web/index.html#androidx.lifecycle:lifecycle-livedata:2.7.0) | 2.7.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.lifecycle:lifecycle-livedata-core](https://maven.google.com/web/index.html#androidx.lifecycle:lifecycle-livedata-core:2.7.0) | 2.7.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.lifecycle:lifecycle-livedata-core-ktx](https://maven.google.com/web/index.html#androidx.lifecycle:lifecycle-livedata-core-ktx:2.7.0) | 2.7.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.lifecycle:lifecycle-process](https://maven.google.com/web/index.html#androidx.lifecycle:lifecycle-process:2.7.0) | 2.7.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.lifecycle:lifecycle-runtime](https://maven.google.com/web/index.html#androidx.lifecycle:lifecycle-runtime:2.7.0) | 2.7.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.lifecycle:lifecycle-viewmodel](https://maven.google.com/web/index.html#androidx.lifecycle:lifecycle-viewmodel:2.7.0) | 2.7.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.lifecycle:lifecycle-viewmodel-savedstate](https://maven.google.com/web/index.html#androidx.lifecycle:lifecycle-viewmodel-savedstate:2.7.0) | 2.7.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.loader:loader](https://maven.google.com/web/index.html#androidx.loader:loader:1.0.0) | 1.0.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.media3:media3-common](https://maven.google.com/web/index.html#androidx.media3:media3-common:1.9.0) | 1.9.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.media3:media3-container](https://maven.google.com/web/index.html#androidx.media3:media3-container:1.9.0) | 1.9.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.media3:media3-muxer](https://maven.google.com/web/index.html#androidx.media3:media3-muxer:1.9.0) | 1.9.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.navigationevent:navigationevent](https://maven.google.com/web/index.html#androidx.navigationevent:navigationevent:1.0.0) | 1.0.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.navigationevent:navigationevent-android](https://maven.google.com/web/index.html#androidx.navigationevent:navigationevent-android:1.0.0) | 1.0.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.profileinstaller:profileinstaller](https://maven.google.com/web/index.html#androidx.profileinstaller:profileinstaller:1.4.0) | 1.4.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.savedstate:savedstate](https://maven.google.com/web/index.html#androidx.savedstate:savedstate:1.2.1) | 1.2.1 | The Apache Software License, Version 2.0 |
| Android | [androidx.startup:startup-runtime](https://maven.google.com/web/index.html#androidx.startup:startup-runtime:1.1.1) | 1.1.1 | The Apache Software License, Version 2.0 |
| Android | [androidx.tracing:tracing](https://maven.google.com/web/index.html#androidx.tracing:tracing:1.3.0) | 1.3.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.tracing:tracing-android](https://maven.google.com/web/index.html#androidx.tracing:tracing-android:1.3.0) | 1.3.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.tracing:tracing-ktx](https://maven.google.com/web/index.html#androidx.tracing:tracing-ktx:1.3.0) | 1.3.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.versionedparcelable:versionedparcelable](https://maven.google.com/web/index.html#androidx.versionedparcelable:versionedparcelable:1.1.1) | 1.1.1 | The Apache Software License, Version 2.0 |
| Android | [androidx.viewpager:viewpager](https://maven.google.com/web/index.html#androidx.viewpager:viewpager:1.0.0) | 1.0.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.window.extensions.core:core](https://maven.google.com/web/index.html#androidx.window.extensions.core:core:1.0.0) | 1.0.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.window:window](https://maven.google.com/web/index.html#androidx.window:window:1.2.0) | 1.2.0 | The Apache Software License, Version 2.0 |
| Android | [androidx.window:window-java](https://maven.google.com/web/index.html#androidx.window:window-java:1.2.0) | 1.2.0 | The Apache Software License, Version 2.0 |
| Android | [com.android.tools.build:gradle](https://maven.google.com/web/index.html#com.android.tools.build:gradle:9.1.0) | 9.1.0 | The Apache Software License, Version 2.0 |
| Android | [com.getkeepsafe.relinker:relinker](https://central.sonatype.com/artifact/com.getkeepsafe.relinker/relinker/1.4.5) | 1.4.5 | The Apache Software License, Version 2.0 |
| Android | [com.google.auto.value:auto-value-annotations](https://central.sonatype.com/artifact/com.google.auto.value/auto-value-annotations/1.6.3) | 1.6.3 | Apache 2.0 |
| Android | [com.google.dagger:dagger](https://central.sonatype.com/artifact/com.google.dagger/dagger/2.59) | 2.59 | Apache 2.0 |
| Android | [com.google.errorprone:error_prone_annotations](https://central.sonatype.com/artifact/com.google.errorprone/error_prone_annotations/2.41.0) | 2.41.0 | Apache 2.0 |
| Android | [com.google.guava:failureaccess](https://central.sonatype.com/artifact/com.google.guava/failureaccess/1.0.3) | 1.0.3 | Apache License, Version 2.0 |
| Android | [com.google.guava:guava](https://central.sonatype.com/artifact/com.google.guava/guava/33.5.0-android) | 33.5.0-android | Apache License, Version 2.0 |
| Android | [com.google.guava:listenablefuture](https://central.sonatype.com/artifact/com.google.guava/listenablefuture/9999.0-empty-to-avoid-conflict-with-guava) | 9999.0-empty-to-avoid-conflict-with-guava | The Apache Software License, Version 2.0 |
| Android | [com.google.j2objc:j2objc-annotations](https://central.sonatype.com/artifact/com.google.j2objc/j2objc-annotations/3.1) | 3.1 | Apache License, Version 2.0 |
| Android | [io.flutter:arm64_v8a_release](https://central.sonatype.com/artifact/io.flutter/arm64_v8a_release/1.0.0-deb287481e3ce9468f3434937ced4240a70539ca) | 1.0.0-deb287481e3ce9468f3434937ced4240a70539ca | BSD-3-Clause (Flutter engine; bundled third-party notices) |
| Android | [io.flutter:flutter_embedding_release](https://central.sonatype.com/artifact/io.flutter/flutter_embedding_release/1.0.0-deb287481e3ce9468f3434937ced4240a70539ca) | 1.0.0-deb287481e3ce9468f3434937ced4240a70539ca | BSD-3-Clause (Flutter engine; bundled third-party notices) |
| Android | [jakarta.inject:jakarta.inject-api](https://central.sonatype.com/artifact/jakarta.inject/jakarta.inject-api/2.0.1) | 2.0.1 | The Apache Software License, Version 2.0 |
| Android | [javax.inject:javax.inject](https://central.sonatype.com/artifact/javax.inject/javax.inject/1) | 1 | Apache-2.0 (upstream README license section; absent from POM) |
| Android | [junit:junit](https://central.sonatype.com/artifact/junit/junit/4.13.2) | 4.13.2 | Eclipse Public License 1.0 — EPL-1.0 copyleft; host-test dependency only, not packaged in production. |
| Android | [org.hamcrest:hamcrest-core](https://central.sonatype.com/artifact/org.hamcrest/hamcrest-core/1.3) | 1.3 | New BSD License |
| Android | [org.jetbrains.kotlin:kotlin-bom](https://central.sonatype.com/artifact/org.jetbrains.kotlin/kotlin-bom/1.8.0) | 1.8.0 | The Apache Software License, Version 2.0 |
| Android | [org.jetbrains.kotlin:kotlin-gradle-plugin](https://central.sonatype.com/artifact/org.jetbrains.kotlin/kotlin-gradle-plugin/2.4.20) | 2.4.20 | Apache-2.0 |
| Android | [org.jetbrains.kotlin:kotlin-stdlib](https://central.sonatype.com/artifact/org.jetbrains.kotlin/kotlin-stdlib/2.4.20) | 2.4.20 | Apache-2.0 |
| Android | [org.jetbrains.kotlinx:atomicfu](https://central.sonatype.com/artifact/org.jetbrains.kotlinx/atomicfu/0.28.0) | 0.28.0 | Apache-2.0 |
| Android | [org.jetbrains.kotlinx:atomicfu-jvm](https://central.sonatype.com/artifact/org.jetbrains.kotlinx/atomicfu-jvm/0.28.0) | 0.28.0 | Apache-2.0 |
| Android | [org.jetbrains.kotlinx:kotlinx-coroutines-android](https://central.sonatype.com/artifact/org.jetbrains.kotlinx/kotlinx-coroutines-android/1.9.0) | 1.9.0 | The Apache Software License, Version 2.0 |
| Android | [org.jetbrains.kotlinx:kotlinx-coroutines-bom](https://central.sonatype.com/artifact/org.jetbrains.kotlinx/kotlinx-coroutines-bom/1.9.0) | 1.9.0 | The Apache Software License, Version 2.0 |
| Android | [org.jetbrains.kotlinx:kotlinx-coroutines-core](https://central.sonatype.com/artifact/org.jetbrains.kotlinx/kotlinx-coroutines-core/1.9.0) | 1.9.0 | The Apache Software License, Version 2.0 |
| Android | [org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm](https://central.sonatype.com/artifact/org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm/1.9.0) | 1.9.0 | The Apache Software License, Version 2.0 |
| Android | [org.jetbrains:annotations](https://central.sonatype.com/artifact/org.jetbrains/annotations/23.0.0) | 23.0.0 | The Apache Software License, Version 2.0 |
| Android | [org.jspecify:jspecify](https://central.sonatype.com/artifact/org.jspecify/jspecify/1.0.0) | 1.0.0 | The Apache License, Version 2.0 |
| Dart | [_fe_analyzer_shared](https://pub.dev/packages/_fe_analyzer_shared/versions/109.0.0) | 109.0.0 | BSD |
| Dart | [analyzer](https://pub.dev/packages/analyzer/versions/14.5.0) | 14.5.0 | BSD |
| Dart | [analyzer_buffer](https://pub.dev/packages/analyzer_buffer/versions/0.3.4) | 0.3.4 | MIT |
| Dart | [archive](https://pub.dev/packages/archive/versions/4.5.2) | 4.5.2 | MIT + BSD — Includes bundled third-party notices; see upstream LICENSE files. |
| Dart | [args](https://pub.dev/packages/args/versions/2.7.0) | 2.7.0 | BSD |
| Dart | [async](https://pub.dev/packages/async/versions/2.13.1) | 2.13.1 | BSD |
| Dart | [boolean_selector](https://pub.dev/packages/boolean_selector/versions/2.1.2) | 2.1.2 | BSD |
| Dart | [build](https://pub.dev/packages/build/versions/4.0.11) | 4.0.11 | BSD |
| Dart | [build_cli_annotations](https://pub.dev/packages/build_cli_annotations/versions/2.1.1) | 2.1.1 | MIT |
| Dart | [build_config](https://pub.dev/packages/build_config/versions/1.3.3) | 1.3.3 | BSD |
| Dart | [build_daemon](https://pub.dev/packages/build_daemon/versions/4.1.6) | 4.1.6 | BSD |
| Dart | [build_runner](https://pub.dev/packages/build_runner/versions/2.16.2) | 2.16.2 | BSD |
| Dart | [built_collection](https://pub.dev/packages/built_collection/versions/5.1.2) | 5.1.2 | BSD |
| Dart | [built_value](https://pub.dev/packages/built_value/versions/8.13.0) | 8.13.0 | BSD |
| Dart | [camera](https://pub.dev/packages/camera/versions/0.12.1) | 0.12.1 | BSD |
| Dart | [camera_android_camerax](https://pub.dev/packages/camera_android_camerax/versions/0.7.5+1) | 0.7.5+1 | BSD |
| Dart | [camera_avfoundation](https://pub.dev/packages/camera_avfoundation/versions/0.10.3+1) | 0.10.3+1 | BSD |
| Dart | [camera_platform_interface](https://pub.dev/packages/camera_platform_interface/versions/2.15.0) | 2.15.0 | BSD |
| Dart | [camera_web](https://pub.dev/packages/camera_web/versions/0.3.5+6) | 0.3.5+6 | BSD |
| Dart | [characters](https://pub.dev/packages/characters/versions/1.4.1) | 1.4.1 | BSD |
| Dart | [checked_yaml](https://pub.dev/packages/checked_yaml/versions/2.0.4) | 2.0.4 | BSD |
| Dart | [clock](https://pub.dev/packages/clock/versions/1.1.3) | 1.1.3 | Apache-2.0 |
| Dart | [collection](https://pub.dev/packages/collection/versions/1.19.1) | 1.19.1 | BSD |
| Dart | [convert](https://pub.dev/packages/convert/versions/3.1.2) | 3.1.2 | BSD |
| Dart | [cross_file](https://pub.dev/packages/cross_file/versions/0.3.5+5) | 0.3.5+5 | BSD |
| Dart | [crypto](https://pub.dev/packages/crypto/versions/3.0.7) | 3.0.7 | BSD |
| Dart | [dart_style](https://pub.dev/packages/dart_style/versions/3.1.13) | 3.1.13 | BSD |
| Dart | [fake_async](https://pub.dev/packages/fake_async/versions/1.3.3) | 1.3.3 | Apache-2.0 |
| Dart | [ffi](https://pub.dev/packages/ffi/versions/2.2.0) | 2.2.0 | BSD |
| Dart | [file](https://pub.dev/packages/file/versions/7.0.1) | 7.0.1 | BSD |
| Dart | [file_selector_linux](https://pub.dev/packages/file_selector_linux/versions/0.9.4+1) | 0.9.4+1 | BSD |
| Dart | [file_selector_macos](https://pub.dev/packages/file_selector_macos/versions/0.9.5+1) | 0.9.5+1 | BSD |
| Dart | [file_selector_platform_interface](https://pub.dev/packages/file_selector_platform_interface/versions/2.7.0) | 2.7.0 | BSD |
| Dart | [file_selector_windows](https://pub.dev/packages/file_selector_windows/versions/0.9.3+6) | 0.9.3+6 | BSD |
| Dart | [fixnum](https://pub.dev/packages/fixnum/versions/1.1.1) | 1.1.1 | BSD |
| Dart | [flutter](https://github.com/flutter/flutter) | SDK 3.47.7 | BSD |
| Dart | [flutter_driver](https://github.com/flutter/flutter) | SDK 3.47.7 | BSD |
| Dart | [flutter_lints](https://pub.dev/packages/flutter_lints/versions/6.0.0) | 6.0.0 | BSD |
| Dart | [flutter_plugin_android_lifecycle](https://pub.dev/packages/flutter_plugin_android_lifecycle/versions/2.0.35) | 2.0.35 | BSD |
| Dart | [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge/versions/2.13.0) | 2.13.0 | MIT |
| Dart | [flutter_test](https://github.com/flutter/flutter) | SDK 3.47.7 | BSD |
| Dart | [flutter_web_plugins](https://github.com/flutter/flutter) | SDK 3.47.7 | BSD |
| Dart | [flutter_zxing](https://pub.dev/packages/flutter_zxing/versions/3.1.0) | 3.1.0 | MIT |
| Dart | [freezed](https://pub.dev/packages/freezed/versions/4.0.2) | 4.0.2 | MIT |
| Dart | [freezed_annotation](https://pub.dev/packages/freezed_annotation/versions/3.1.0) | 3.1.0 | MIT |
| Dart | [fuchsia_remote_debug_protocol](https://github.com/flutter/flutter) | SDK 3.47.7 | BSD |
| Dart | [glob](https://pub.dev/packages/glob/versions/2.2.0) | 2.2.0 | BSD |
| Dart | [graphs](https://pub.dev/packages/graphs/versions/2.3.2) | 2.3.2 | BSD |
| Dart | [http](https://pub.dev/packages/http/versions/1.6.0) | 1.6.0 | BSD |
| Dart | [http_multi_server](https://pub.dev/packages/http_multi_server/versions/3.2.2) | 3.2.2 | BSD |
| Dart | [http_parser](https://pub.dev/packages/http_parser/versions/4.1.2) | 4.1.2 | BSD |
| Dart | [image](https://pub.dev/packages/image/versions/4.12.0) | 4.12.0 | Apache-2.0 + MIT + BSD — Includes bundled third-party notices; see upstream LICENSE files. |
| Dart | [image_picker](https://pub.dev/packages/image_picker/versions/1.2.4) | 1.2.4 | Apache-2.0 + BSD |
| Dart | [image_picker_android](https://pub.dev/packages/image_picker_android/versions/0.8.13+25) | 0.8.13+25 | Apache-2.0 + BSD |
| Dart | [image_picker_for_web](https://pub.dev/packages/image_picker_for_web/versions/3.1.1) | 3.1.1 | BSD |
| Dart | [image_picker_ios](https://pub.dev/packages/image_picker_ios/versions/0.8.13+12) | 0.8.13+12 | Apache-2.0 + BSD |
| Dart | [image_picker_linux](https://pub.dev/packages/image_picker_linux/versions/0.2.2) | 0.2.2 | BSD |
| Dart | [image_picker_macos](https://pub.dev/packages/image_picker_macos/versions/0.2.2+1) | 0.2.2+1 | BSD |
| Dart | [image_picker_platform_interface](https://pub.dev/packages/image_picker_platform_interface/versions/2.11.2) | 2.11.2 | BSD |
| Dart | [image_picker_windows](https://pub.dev/packages/image_picker_windows/versions/0.2.2) | 0.2.2 | BSD |
| Dart | [integration_test](https://github.com/flutter/flutter) | SDK 3.47.7 | BSD |
| Dart | [io](https://pub.dev/packages/io/versions/1.1.0) | 1.1.0 | BSD |
| Dart | [json_annotation](https://pub.dev/packages/json_annotation/versions/4.12.0) | 4.12.0 | BSD |
| Dart | [leak_tracker](https://pub.dev/packages/leak_tracker/versions/11.0.2) | 11.0.2 | BSD |
| Dart | [leak_tracker_flutter_testing](https://pub.dev/packages/leak_tracker_flutter_testing/versions/3.0.10) | 3.0.10 | BSD |
| Dart | [leak_tracker_testing](https://pub.dev/packages/leak_tracker_testing/versions/3.0.2) | 3.0.2 | BSD |
| Dart | [lints](https://pub.dev/packages/lints/versions/6.1.0) | 6.1.0 | BSD |
| Dart | [logging](https://pub.dev/packages/logging/versions/1.3.0) | 1.3.0 | BSD |
| Dart | [matcher](https://pub.dev/packages/matcher/versions/0.12.20) | 0.12.20 | BSD |
| Dart | [material_color_utilities](https://pub.dev/packages/material_color_utilities/versions/0.13.0) | 0.13.0 | Apache-2.0 |
| Dart | [material_symbols_icons](https://pub.dev/packages/material_symbols_icons/versions/4.2960.0) | 4.2960.0 | Apache-2.0 |
| Dart | [meta](https://pub.dev/packages/meta/versions/1.18.3) | 1.18.3 | BSD |
| Dart | [mime](https://pub.dev/packages/mime/versions/2.1.0) | 2.1.0 | BSD |
| Dart | [package_config](https://pub.dev/packages/package_config/versions/3.0.0) | 3.0.0 | BSD |
| Dart | [path](https://pub.dev/packages/path/versions/1.9.1) | 1.9.1 | BSD |
| Dart | [platform](https://pub.dev/packages/platform/versions/3.2.0) | 3.2.0 | BSD |
| Dart | [plugin_platform_interface](https://pub.dev/packages/plugin_platform_interface/versions/2.1.8) | 2.1.8 | BSD |
| Dart | [pool](https://pub.dev/packages/pool/versions/1.5.3) | 1.5.3 | BSD |
| Dart | [posix](https://pub.dev/packages/posix/versions/6.5.2) | 6.5.2 | MIT |
| Dart | [pretty_qr_code](https://pub.dev/packages/pretty_qr_code/versions/3.6.0) | 3.6.0 | MIT |
| Dart | [process](https://pub.dev/packages/process/versions/5.0.6) | 5.0.6 | BSD |
| Dart | [pub_semver](https://pub.dev/packages/pub_semver/versions/2.2.1) | 2.2.1 | BSD |
| Dart | [pubspec_parse](https://pub.dev/packages/pubspec_parse/versions/1.6.0) | 1.6.0 | BSD |
| Dart | [qr](https://pub.dev/packages/qr/versions/3.0.2) | 3.0.2 | BSD |
| Dart | [shelf](https://pub.dev/packages/shelf/versions/1.4.2) | 1.4.2 | BSD |
| Dart | [shelf_web_socket](https://pub.dev/packages/shelf_web_socket/versions/3.0.0) | 3.0.0 | BSD |
| Dart | [sky_engine](https://github.com/flutter/flutter) | SDK 3.47.7 | Apache-2.0 + MIT + BSD — Includes bundled third-party notices; see upstream LICENSE files. |
| Dart | [source_gen](https://pub.dev/packages/source_gen/versions/4.3.0) | 4.3.0 | BSD |
| Dart | [source_span](https://pub.dev/packages/source_span/versions/1.10.2) | 1.10.2 | BSD |
| Dart | [stack_trace](https://pub.dev/packages/stack_trace/versions/1.12.2) | 1.12.2 | BSD |
| Dart | [stream_channel](https://pub.dev/packages/stream_channel/versions/2.1.4) | 2.1.4 | BSD |
| Dart | [stream_transform](https://pub.dev/packages/stream_transform/versions/2.1.2) | 2.1.2 | BSD |
| Dart | [string_scanner](https://pub.dev/packages/string_scanner/versions/1.4.1) | 1.4.1 | BSD |
| Dart | [sync_http](https://pub.dev/packages/sync_http/versions/0.3.1) | 0.3.1 | BSD |
| Dart | [term_glyph](https://pub.dev/packages/term_glyph/versions/1.2.2) | 1.2.2 | BSD |
| Dart | [test_api](https://pub.dev/packages/test_api/versions/0.7.12) | 0.7.12 | BSD |
| Dart | [typed_data](https://pub.dev/packages/typed_data/versions/1.4.0) | 1.4.0 | BSD |
| Dart | [vector_math](https://pub.dev/packages/vector_math/versions/2.4.0) | 2.4.0 | BSD |
| Dart | [vm_service](https://pub.dev/packages/vm_service/versions/15.3.0) | 15.3.0 | BSD |
| Dart | [watcher](https://pub.dev/packages/watcher/versions/1.2.1) | 1.2.1 | BSD |
| Dart | [web](https://pub.dev/packages/web/versions/1.1.1) | 1.1.1 | BSD |
| Dart | [web_socket](https://pub.dev/packages/web_socket/versions/1.0.1) | 1.0.1 | BSD |
| Dart | [web_socket_channel](https://pub.dev/packages/web_socket_channel/versions/3.0.3) | 3.0.3 | BSD |
| Dart | [webdriver](https://pub.dev/packages/webdriver/versions/3.2.0) | 3.2.0 | Apache-2.0 |
| Dart | [yaml](https://pub.dev/packages/yaml/versions/3.1.4) | 3.1.4 | MIT |
| Native/assets | [Arimo embedded font](https://github.com/zint/zint/blob/master/backend/fonts/normal_woff2.h) | Zint normal_woff2.h | Apache-2.0 — Copyright Steve Matteson; embedded by Zint svg.c. |
| Native/assets | [Flutter default icons](https://flutter.dev/brand) | Flutter 3.47.7 | BSD-3-Clause; trademark policy also applies — Unmodified generated dev icons; no endorsement implied. |
| Native/assets | [LLVM libc++](https://github.com/llvm/llvm-project/blob/main/libcxx/LICENSE.TXT) | NDK 30.0.16248370 | Apache-2.0 WITH LLVM-exception — Android C++ runtime. |
| Native/assets | [Material Symbols / cookdex pan artwork](https://github.com/google/material-design-icons) | 4.2960.0 | Apache-2.0 — Pan glyph is rasterized by flutter/tool/generate_branding.dart. |
| Native/assets | [OCR-B embedded font](https://github.com/zint/zint/blob/master/backend/fonts/upcean_woff2.h) | Zint upcean_woff2.h | Unrestricted use/copy/modification/distribution grant — Retain upstream embedded font notice; distinct from Zint backend BSD terms. |
| Native/assets | [SQLite](https://www.sqlite.org/copyright.html) | bundled by libsqlite3-sys 0.36.0 | Public domain — Bundled amalgamation in libsqlite3-sys; Rust wrapper is MIT. |
| Native/assets | [ZXing-C++](https://github.com/zxing-cpp/zxing-cpp) | 3.1.1 (flutter_zxing 3.1.0) | Apache-2.0 — Vendored upstream dependency, not copied into this source repository. |
| Native/assets | [Zint backend](https://github.com/zint/zint/blob/master/LICENSE) | bundled by ZXing-C++ | BSD-3-Clause — GPL frontend/Qt source is not compiled. ZXing core CMake selects backend files only. |
| Native/assets | [libzueci](https://github.com/zxing-cpp/zxing-cpp) | bundled by ZXing-C++ | BSD-3-Clause AND MIT — Includes the Hoehrmann UTF-8 decoder under MIT; see bundled header notices. |
| Rust | [addr2line](https://crates.io/crates/addr2line/0.25.1) | 0.25.1 | Apache-2.0 OR MIT |
| Rust | [adler2](https://crates.io/crates/adler2/2.0.1) | 2.0.1 | 0BSD OR MIT OR Apache-2.0 |
| Rust | [aead](https://crates.io/crates/aead/0.5.2) | 0.5.2 | MIT OR Apache-2.0 |
| Rust | [aes](https://crates.io/crates/aes/0.8.4) | 0.8.4 | MIT OR Apache-2.0 |
| Rust | [aes-gcm](https://crates.io/crates/aes-gcm/0.10.3) | 0.10.3 | Apache-2.0 OR MIT |
| Rust | [aho-corasick](https://crates.io/crates/aho-corasick/1.1.5) | 1.1.5 | Unlicense OR MIT |
| Rust | [allo-isolate](https://crates.io/crates/allo-isolate/0.1.27) | 0.1.27 | Apache-2.0 |
| Rust | [android_log-sys](https://crates.io/crates/android_log-sys/0.3.2) | 0.3.2 | MIT OR Apache-2.0 |
| Rust | [android_logger](https://crates.io/crates/android_logger/0.15.1) | 0.15.1 | MIT OR Apache-2.0 |
| Rust | [android_system_properties](https://crates.io/crates/android_system_properties/0.1.6) | 0.1.6 | MIT OR Apache-2.0 |
| Rust | [anyhow](https://crates.io/crates/anyhow/1.0.104) | 1.0.104 | MIT OR Apache-2.0 |
| Rust | [atomic](https://crates.io/crates/atomic/0.5.3) | 0.5.3 | Apache-2.0/MIT |
| Rust | [autocfg](https://crates.io/crates/autocfg/1.5.1) | 1.5.1 | Apache-2.0 OR MIT |
| Rust | [backtrace](https://crates.io/crates/backtrace/0.3.76) | 0.3.76 | MIT OR Apache-2.0 |
| Rust | [base64](https://crates.io/crates/base64/0.22.1) | 0.22.1 | MIT OR Apache-2.0 |
| Rust | [bitflags](https://crates.io/crates/bitflags/2.13.2) | 2.13.2 | MIT OR Apache-2.0 |
| Rust | [blake2](https://crates.io/crates/blake2/0.10.6) | 0.10.6 | MIT OR Apache-2.0 |
| Rust | [block-buffer](https://crates.io/crates/block-buffer/0.10.4) | 0.10.4 | MIT OR Apache-2.0 |
| Rust | [build-target](https://crates.io/crates/build-target/0.4.0) | 0.4.0 | MIT |
| Rust | [bumpalo](https://crates.io/crates/bumpalo/3.20.3) | 3.20.3 | MIT OR Apache-2.0 |
| Rust | [bytemuck](https://crates.io/crates/bytemuck/1.25.2) | 1.25.2 | Zlib OR Apache-2.0 OR MIT |
| Rust | [byteorder](https://crates.io/crates/byteorder/1.5.0) | 1.5.0 | Unlicense OR MIT |
| Rust | [cc](https://crates.io/crates/cc/1.6.0) | 1.6.0 | MIT OR Apache-2.0 |
| Rust | [cfg-if](https://crates.io/crates/cfg-if/1.0.5) | 1.0.5 | MIT OR Apache-2.0 |
| Rust | [chacha20](https://crates.io/crates/chacha20/0.9.1) | 0.9.1 | Apache-2.0 OR MIT |
| Rust | [chacha20poly1305](https://crates.io/crates/chacha20poly1305/0.10.1) | 0.10.1 | Apache-2.0 OR MIT |
| Rust | [chrono](https://crates.io/crates/chrono/0.4.45) | 0.4.45 | MIT OR Apache-2.0 |
| Rust | [cipher](https://crates.io/crates/cipher/0.4.4) | 0.4.4 | MIT OR Apache-2.0 |
| Rust | [console_error_panic_hook](https://crates.io/crates/console_error_panic_hook/0.1.7) | 0.1.7 | Apache-2.0/MIT |
| Rust | [core-foundation-sys](https://crates.io/crates/core-foundation-sys/0.8.7) | 0.8.7 | MIT OR Apache-2.0 |
| Rust | [cpufeatures](https://crates.io/crates/cpufeatures/0.2.17) | 0.2.17 | MIT OR Apache-2.0 |
| Rust | [crc32fast](https://crates.io/crates/crc32fast/1.5.2) | 1.5.2 | MIT OR Apache-2.0 |
| Rust | [crypto-common](https://crates.io/crates/crypto-common/0.1.7) | 0.1.7 | MIT OR Apache-2.0 |
| Rust | [ctr](https://crates.io/crates/ctr/0.9.2) | 0.9.2 | MIT OR Apache-2.0 |
| Rust | [curve25519-dalek](https://crates.io/crates/curve25519-dalek/4.1.3) | 4.1.3 | BSD-3-Clause |
| Rust | [curve25519-dalek-derive](https://crates.io/crates/curve25519-dalek-derive/0.1.1) | 0.1.1 | MIT/Apache-2.0 |
| Rust | [dart-sys](https://crates.io/crates/dart-sys/4.1.5) | 4.1.5 | MIT OR Apache-2.0 |
| Rust | [dashmap](https://crates.io/crates/dashmap/5.5.3) | 5.5.3 | MIT |
| Rust | [delegate-attr](https://crates.io/crates/delegate-attr/0.3.1) | 0.3.1 | MIT |
| Rust | [digest](https://crates.io/crates/digest/0.10.7) | 0.10.7 | MIT OR Apache-2.0 |
| Rust | [displaydoc](https://crates.io/crates/displaydoc/0.2.7) | 0.2.7 | MIT OR Apache-2.0 |
| Rust | [env_filter](https://crates.io/crates/env_filter/0.1.4) | 0.1.4 | MIT OR Apache-2.0 |
| Rust | [fallible-iterator](https://crates.io/crates/fallible-iterator/0.3.0) | 0.3.0 | MIT/Apache-2.0 |
| Rust | [fallible-streaming-iterator](https://crates.io/crates/fallible-streaming-iterator/0.1.9) | 0.1.9 | MIT/Apache-2.0 |
| Rust | [fiat-crypto](https://crates.io/crates/fiat-crypto/0.2.9) | 0.2.9 | MIT OR Apache-2.0 OR BSD-1-Clause |
| Rust | [find-msvc-tools](https://crates.io/crates/find-msvc-tools/0.1.14) | 0.1.14 | MIT OR Apache-2.0 |
| Rust | [flate2](https://crates.io/crates/flate2/1.1.10) | 1.1.10 | MIT OR Apache-2.0 |
| Rust | [flutter_rust_bridge](https://crates.io/crates/flutter_rust_bridge/2.13.0) | 2.13.0 | MIT |
| Rust | [flutter_rust_bridge_macros](https://crates.io/crates/flutter_rust_bridge_macros/2.13.0) | 2.13.0 | MIT |
| Rust | [foldhash](https://crates.io/crates/foldhash/0.2.0) | 0.2.0 | Zlib |
| Rust | [form_urlencoded](https://crates.io/crates/form_urlencoded/1.2.2) | 1.2.2 | MIT OR Apache-2.0 |
| Rust | [futures](https://crates.io/crates/futures/0.3.34) | 0.3.34 | MIT OR Apache-2.0 |
| Rust | [futures-channel](https://crates.io/crates/futures-channel/0.3.34) | 0.3.34 | MIT OR Apache-2.0 |
| Rust | [futures-core](https://crates.io/crates/futures-core/0.3.34) | 0.3.34 | MIT OR Apache-2.0 |
| Rust | [futures-executor](https://crates.io/crates/futures-executor/0.3.34) | 0.3.34 | MIT OR Apache-2.0 |
| Rust | [futures-io](https://crates.io/crates/futures-io/0.3.34) | 0.3.34 | MIT OR Apache-2.0 |
| Rust | [futures-macro](https://crates.io/crates/futures-macro/0.3.34) | 0.3.34 | MIT OR Apache-2.0 |
| Rust | [futures-sink](https://crates.io/crates/futures-sink/0.3.34) | 0.3.34 | MIT OR Apache-2.0 |
| Rust | [futures-task](https://crates.io/crates/futures-task/0.3.34) | 0.3.34 | MIT OR Apache-2.0 |
| Rust | [futures-util](https://crates.io/crates/futures-util/0.3.34) | 0.3.34 | MIT OR Apache-2.0 |
| Rust | [generic-array](https://crates.io/crates/generic-array/0.14.7) | 0.14.7 | MIT |
| Rust | [getrandom](https://crates.io/crates/getrandom/0.2.17) | 0.2.17 | MIT OR Apache-2.0 |
| Rust | [getrandom](https://crates.io/crates/getrandom/0.3.4) | 0.3.4 | MIT OR Apache-2.0 |
| Rust | [getrandom](https://crates.io/crates/getrandom/0.4.3) | 0.4.3 | MIT OR Apache-2.0 |
| Rust | [ghash](https://crates.io/crates/ghash/0.5.1) | 0.5.1 | Apache-2.0 OR MIT |
| Rust | [gimli](https://crates.io/crates/gimli/0.32.3) | 0.32.3 | MIT OR Apache-2.0 |
| Rust | [hashbrown](https://crates.io/crates/hashbrown/0.14.5) | 0.14.5 | MIT OR Apache-2.0 |
| Rust | [hashbrown](https://crates.io/crates/hashbrown/0.16.1) | 0.16.1 | MIT OR Apache-2.0 |
| Rust | [hashlink](https://crates.io/crates/hashlink/0.11.1) | 0.11.1 | MIT OR Apache-2.0 |
| Rust | [hermit-abi](https://crates.io/crates/hermit-abi/0.5.3) | 0.5.3 | MIT OR Apache-2.0 |
| Rust | [hex](https://crates.io/crates/hex/0.4.3) | 0.4.3 | MIT OR Apache-2.0 |
| Rust | [iana-time-zone](https://crates.io/crates/iana-time-zone/0.1.65) | 0.1.65 | MIT OR Apache-2.0 |
| Rust | [iana-time-zone-haiku](https://crates.io/crates/iana-time-zone-haiku/0.1.2) | 0.1.2 | MIT OR Apache-2.0 |
| Rust | [icu_collections](https://crates.io/crates/icu_collections/2.3.0) | 2.3.0 | Unicode-3.0 |
| Rust | [icu_locale_core](https://crates.io/crates/icu_locale_core/2.3.0) | 2.3.0 | Unicode-3.0 |
| Rust | [icu_normalizer](https://crates.io/crates/icu_normalizer/2.3.0) | 2.3.0 | Unicode-3.0 |
| Rust | [icu_normalizer_data](https://crates.io/crates/icu_normalizer_data/2.3.0) | 2.3.0 | Unicode-3.0 |
| Rust | [icu_properties](https://crates.io/crates/icu_properties/2.3.0) | 2.3.0 | Unicode-3.0 |
| Rust | [icu_properties_data](https://crates.io/crates/icu_properties_data/2.3.0) | 2.3.0 | Unicode-3.0 |
| Rust | [icu_provider](https://crates.io/crates/icu_provider/2.3.1) | 2.3.1 | Unicode-3.0 |
| Rust | [idna](https://crates.io/crates/idna/1.1.0) | 1.1.0 | MIT OR Apache-2.0 |
| Rust | [idna_adapter](https://crates.io/crates/idna_adapter/1.2.2) | 1.2.2 | Apache-2.0 OR MIT |
| Rust | [if-addrs](https://crates.io/crates/if-addrs/0.15.0) | 0.15.0 | MIT OR BSD-3-Clause |
| Rust | [inout](https://crates.io/crates/inout/0.1.4) | 0.1.4 | MIT OR Apache-2.0 |
| Rust | [itoa](https://crates.io/crates/itoa/1.0.18) | 1.0.18 | MIT OR Apache-2.0 |
| Rust | [js-sys](https://crates.io/crates/js-sys/0.3.106) | 0.3.106 | MIT OR Apache-2.0 |
| Rust | [lazy_static](https://crates.io/crates/lazy_static/1.5.1) | 1.5.1 | MIT OR Apache-2.0 |
| Rust | [libc](https://crates.io/crates/libc/0.2.190) | 0.2.190 | MIT OR Apache-2.0 |
| Rust | [libsqlite3-sys](https://crates.io/crates/libsqlite3-sys/0.36.0) | 0.36.0 | MIT |
| Rust | [litemap](https://crates.io/crates/litemap/0.8.3) | 0.8.3 | Unicode-3.0 |
| Rust | [lock_api](https://crates.io/crates/lock_api/0.4.14) | 0.4.14 | MIT OR Apache-2.0 |
| Rust | [log](https://crates.io/crates/log/0.4.34) | 0.4.34 | MIT OR Apache-2.0 |
| Rust | [md-5](https://crates.io/crates/md-5/0.10.6) | 0.10.6 | MIT OR Apache-2.0 |
| Rust | [memchr](https://crates.io/crates/memchr/2.8.3) | 2.8.3 | Unlicense OR MIT |
| Rust | [miniz_oxide](https://crates.io/crates/miniz_oxide/0.8.9) | 0.8.9 | MIT OR Zlib OR Apache-2.0 |
| Rust | [miniz_oxide](https://crates.io/crates/miniz_oxide/0.9.1) | 0.9.1 | MIT OR Zlib OR Apache-2.0 |
| Rust | [num-traits](https://crates.io/crates/num-traits/0.2.19) | 0.2.19 | MIT OR Apache-2.0 |
| Rust | [num_cpus](https://crates.io/crates/num_cpus/1.17.0) | 1.17.0 | MIT OR Apache-2.0 |
| Rust | [object](https://crates.io/crates/object/0.37.3) | 0.37.3 | Apache-2.0 OR MIT |
| Rust | [once_cell](https://crates.io/crates/once_cell/1.21.4) | 1.21.4 | MIT OR Apache-2.0 |
| Rust | [opaque-debug](https://crates.io/crates/opaque-debug/0.3.1) | 0.3.1 | MIT OR Apache-2.0 |
| Rust | [oslog](https://crates.io/crates/oslog/0.2.0) | 0.2.0 | MIT |
| Rust | [parking_lot_core](https://crates.io/crates/parking_lot_core/0.9.12) | 0.9.12 | MIT OR Apache-2.0 |
| Rust | [percent-encoding](https://crates.io/crates/percent-encoding/2.3.2) | 2.3.2 | MIT OR Apache-2.0 |
| Rust | [pin-project-lite](https://crates.io/crates/pin-project-lite/0.2.17) | 0.2.17 | Apache-2.0 OR MIT |
| Rust | [pkg-config](https://crates.io/crates/pkg-config/0.3.34) | 0.3.34 | MIT OR Apache-2.0 |
| Rust | [poly1305](https://crates.io/crates/poly1305/0.8.0) | 0.8.0 | Apache-2.0 OR MIT |
| Rust | [polyval](https://crates.io/crates/polyval/0.6.2) | 0.6.2 | Apache-2.0 OR MIT |
| Rust | [portable-atomic](https://crates.io/crates/portable-atomic/1.15.0) | 1.15.0 | Apache-2.0 OR MIT |
| Rust | [potential_utf](https://crates.io/crates/potential_utf/0.1.6) | 0.1.6 | Unicode-3.0 |
| Rust | [proc-macro2](https://crates.io/crates/proc-macro2/1.0.107) | 1.0.107 | MIT OR Apache-2.0 |
| Rust | [quote](https://crates.io/crates/quote/1.0.47) | 1.0.47 | MIT OR Apache-2.0 |
| Rust | [r-efi](https://crates.io/crates/r-efi/5.3.0) | 5.3.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later — MIT option selected; LGPL alternative not used. |
| Rust | [r-efi](https://crates.io/crates/r-efi/6.0.0) | 6.0.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later — MIT option selected; LGPL alternative not used. |
| Rust | [redox_syscall](https://crates.io/crates/redox_syscall/0.5.18) | 0.5.18 | MIT |
| Rust | [regex](https://crates.io/crates/regex/1.13.1) | 1.13.1 | MIT OR Apache-2.0 |
| Rust | [regex-automata](https://crates.io/crates/regex-automata/0.4.18) | 0.4.18 | MIT OR Apache-2.0 |
| Rust | [regex-syntax](https://crates.io/crates/regex-syntax/0.8.11) | 0.8.11 | MIT OR Apache-2.0 |
| Rust | [ring](https://crates.io/crates/ring/0.17.14) | 0.17.14 | Apache-2.0 AND ISC |
| Rust | [rsqlite-vfs](https://crates.io/crates/rsqlite-vfs/0.1.1) | 0.1.1 | MIT |
| Rust | [rusqlite](https://crates.io/crates/rusqlite/0.38.0) | 0.38.0 | MIT |
| Rust | [rustc-demangle](https://crates.io/crates/rustc-demangle/0.1.28) | 0.1.28 | MIT/Apache-2.0 |
| Rust | [rustc_version](https://crates.io/crates/rustc_version/0.4.1) | 0.4.1 | MIT OR Apache-2.0 |
| Rust | [rustversion](https://crates.io/crates/rustversion/1.0.23) | 1.0.23 | MIT OR Apache-2.0 |
| Rust | [scopeguard](https://crates.io/crates/scopeguard/1.2.0) | 1.2.0 | MIT OR Apache-2.0 |
| Rust | [semver](https://crates.io/crates/semver/1.0.28) | 1.0.28 | MIT OR Apache-2.0 |
| Rust | [serde](https://crates.io/crates/serde/1.0.229) | 1.0.229 | MIT OR Apache-2.0 |
| Rust | [serde_core](https://crates.io/crates/serde_core/1.0.229) | 1.0.229 | MIT OR Apache-2.0 |
| Rust | [serde_derive](https://crates.io/crates/serde_derive/1.0.229) | 1.0.229 | MIT OR Apache-2.0 |
| Rust | [serde_json](https://crates.io/crates/serde_json/1.0.151) | 1.0.151 | MIT OR Apache-2.0 |
| Rust | [sha2](https://crates.io/crates/sha2/0.10.9) | 0.10.9 | MIT OR Apache-2.0 |
| Rust | [shlex](https://crates.io/crates/shlex/2.0.1) | 2.0.1 | MIT OR Apache-2.0 |
| Rust | [simd-adler32](https://crates.io/crates/simd-adler32/0.3.10) | 0.3.10 | MIT |
| Rust | [slab](https://crates.io/crates/slab/0.4.12) | 0.4.12 | MIT |
| Rust | [smallvec](https://crates.io/crates/smallvec/1.16.2) | 1.16.2 | MIT OR Apache-2.0 |
| Rust | [snow](https://crates.io/crates/snow/0.10.0) | 0.10.0 | Apache-2.0 OR MIT |
| Rust | [sqlite-wasm-rs](https://crates.io/crates/sqlite-wasm-rs/0.5.5) | 0.5.5 | MIT |
| Rust | [stable_deref_trait](https://crates.io/crates/stable_deref_trait/1.2.1) | 1.2.1 | MIT OR Apache-2.0 |
| Rust | [subtle](https://crates.io/crates/subtle/2.6.1) | 2.6.1 | BSD-3-Clause |
| Rust | [syn](https://crates.io/crates/syn/2.0.119) | 2.0.119 | MIT OR Apache-2.0 |
| Rust | [syn](https://crates.io/crates/syn/3.0.6) | 3.0.6 | MIT OR Apache-2.0 |
| Rust | [synstructure](https://crates.io/crates/synstructure/0.14.0) | 0.14.0 | MIT |
| Rust | [thiserror](https://crates.io/crates/thiserror/2.0.21) | 2.0.21 | MIT OR Apache-2.0 |
| Rust | [thiserror-impl](https://crates.io/crates/thiserror-impl/2.0.21) | 2.0.21 | MIT OR Apache-2.0 |
| Rust | [threadpool](https://crates.io/crates/threadpool/1.8.1) | 1.8.1 | MIT/Apache-2.0 |
| Rust | [tinystr](https://crates.io/crates/tinystr/0.8.4) | 0.8.4 | Unicode-3.0 |
| Rust | [tokio](https://crates.io/crates/tokio/1.53.2) | 1.53.2 | MIT |
| Rust | [typenum](https://crates.io/crates/typenum/1.20.1) | 1.20.1 | MIT OR Apache-2.0 |
| Rust | [unicode-ident](https://crates.io/crates/unicode-ident/1.0.26) | 1.0.26 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| Rust | [universal-hash](https://crates.io/crates/universal-hash/0.5.1) | 0.5.1 | MIT OR Apache-2.0 |
| Rust | [untrusted](https://crates.io/crates/untrusted/0.9.0) | 0.9.0 | ISC |
| Rust | [url](https://crates.io/crates/url/2.5.8) | 2.5.8 | MIT OR Apache-2.0 |
| Rust | [utf8_iter](https://crates.io/crates/utf8_iter/1.0.4) | 1.0.4 | Apache-2.0 OR MIT |
| Rust | [uuid](https://crates.io/crates/uuid/1.27.0) | 1.27.0 | Apache-2.0 OR MIT |
| Rust | [vcpkg](https://crates.io/crates/vcpkg/0.2.15) | 0.2.15 | MIT/Apache-2.0 |
| Rust | [version_check](https://crates.io/crates/version_check/0.9.5) | 0.9.5 | MIT/Apache-2.0 |
| Rust | [wasi](https://crates.io/crates/wasi/0.11.1+wasi-snapshot-preview1) | 0.11.1+wasi-snapshot-preview1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT |
| Rust | [wasip2](https://crates.io/crates/wasip2/1.0.4+wasi-0.2.12) | 1.0.4+wasi-0.2.12 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT |
| Rust | [wasm-bindgen](https://crates.io/crates/wasm-bindgen/0.2.129) | 0.2.129 | MIT OR Apache-2.0 |
| Rust | [wasm-bindgen-futures](https://crates.io/crates/wasm-bindgen-futures/0.4.79) | 0.4.79 | MIT OR Apache-2.0 |
| Rust | [wasm-bindgen-macro](https://crates.io/crates/wasm-bindgen-macro/0.2.129) | 0.2.129 | MIT OR Apache-2.0 |
| Rust | [wasm-bindgen-macro-support](https://crates.io/crates/wasm-bindgen-macro-support/0.2.129) | 0.2.129 | MIT OR Apache-2.0 |
| Rust | [wasm-bindgen-shared](https://crates.io/crates/wasm-bindgen-shared/0.2.129) | 0.2.129 | MIT OR Apache-2.0 |
| Rust | [web-sys](https://crates.io/crates/web-sys/0.3.106) | 0.3.106 | MIT OR Apache-2.0 |
| Rust | [windows-core](https://crates.io/crates/windows-core/0.62.2) | 0.62.2 | MIT OR Apache-2.0 |
| Rust | [windows-implement](https://crates.io/crates/windows-implement/0.60.2) | 0.60.2 | MIT OR Apache-2.0 |
| Rust | [windows-interface](https://crates.io/crates/windows-interface/0.59.3) | 0.59.3 | MIT OR Apache-2.0 |
| Rust | [windows-link](https://crates.io/crates/windows-link/0.2.1) | 0.2.1 | MIT OR Apache-2.0 |
| Rust | [windows-result](https://crates.io/crates/windows-result/0.4.1) | 0.4.1 | MIT OR Apache-2.0 |
| Rust | [windows-strings](https://crates.io/crates/windows-strings/0.5.1) | 0.5.1 | MIT OR Apache-2.0 |
| Rust | [windows-sys](https://crates.io/crates/windows-sys/0.52.0) | 0.52.0 | MIT OR Apache-2.0 |
| Rust | [windows-sys](https://crates.io/crates/windows-sys/0.61.2) | 0.61.2 | MIT OR Apache-2.0 |
| Rust | [windows-targets](https://crates.io/crates/windows-targets/0.52.6) | 0.52.6 | MIT OR Apache-2.0 |
| Rust | [windows_aarch64_gnullvm](https://crates.io/crates/windows_aarch64_gnullvm/0.52.6) | 0.52.6 | MIT OR Apache-2.0 |
| Rust | [windows_aarch64_msvc](https://crates.io/crates/windows_aarch64_msvc/0.52.6) | 0.52.6 | MIT OR Apache-2.0 |
| Rust | [windows_i686_gnu](https://crates.io/crates/windows_i686_gnu/0.52.6) | 0.52.6 | MIT OR Apache-2.0 |
| Rust | [windows_i686_gnullvm](https://crates.io/crates/windows_i686_gnullvm/0.52.6) | 0.52.6 | MIT OR Apache-2.0 |
| Rust | [windows_i686_msvc](https://crates.io/crates/windows_i686_msvc/0.52.6) | 0.52.6 | MIT OR Apache-2.0 |
| Rust | [windows_x86_64_gnu](https://crates.io/crates/windows_x86_64_gnu/0.52.6) | 0.52.6 | MIT OR Apache-2.0 |
| Rust | [windows_x86_64_gnullvm](https://crates.io/crates/windows_x86_64_gnullvm/0.52.6) | 0.52.6 | MIT OR Apache-2.0 |
| Rust | [windows_x86_64_msvc](https://crates.io/crates/windows_x86_64_msvc/0.52.6) | 0.52.6 | MIT OR Apache-2.0 |
| Rust | [wit-bindgen](https://crates.io/crates/wit-bindgen/0.57.1) | 0.57.1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT |
| Rust | [writeable](https://crates.io/crates/writeable/0.6.4) | 0.6.4 | Unicode-3.0 |
| Rust | [yoke](https://crates.io/crates/yoke/0.8.3) | 0.8.3 | Unicode-3.0 |
| Rust | [yoke-derive](https://crates.io/crates/yoke-derive/0.8.4) | 0.8.4 | Unicode-3.0 |
| Rust | [zerofrom](https://crates.io/crates/zerofrom/0.1.8) | 0.1.8 | Unicode-3.0 |
| Rust | [zerofrom-derive](https://crates.io/crates/zerofrom-derive/0.1.8) | 0.1.8 | Unicode-3.0 |
| Rust | [zeroize](https://crates.io/crates/zeroize/1.9.0) | 1.9.0 | Apache-2.0 OR MIT |
| Rust | [zerotrie](https://crates.io/crates/zerotrie/0.2.5) | 0.2.5 | Unicode-3.0 |
| Rust | [zerovec](https://crates.io/crates/zerovec/0.11.8) | 0.11.8 | Unicode-3.0 |
| Rust | [zerovec-derive](https://crates.io/crates/zerovec-derive/0.11.6) | 0.11.6 | Unicode-3.0 |
| Rust | [zlib-rs](https://crates.io/crates/zlib-rs/0.6.8) | 0.6.8 | Zlib |
| Rust | [zmij](https://crates.io/crates/zmij/1.0.23) | 1.0.23 | MIT |
| Tool | [Gitleaks](https://github.com/gitleaks/gitleaks/blob/v8.30.0/LICENSE) | 8.30.0 | MIT — Installed separately, not shipped in the app. |
