//! Offline synthetic fixture runner. The caller supplies the disposable directory.
use cookdex_core::{backup, recipe::Recipe};
fn main() {
    let root = std::path::PathBuf::from(std::env::args().nth(1).expect("fixture directory"));
    let values: Vec<serde_json::Value> =
        serde_json::from_slice(&std::fs::read(root.join("recipes.json")).unwrap()).unwrap();
    let recipes: Vec<Recipe> = values
        .iter()
        .map(|v| Recipe::from_json(&serde_json::to_vec(v).unwrap()).unwrap())
        .collect();
    let manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(root.join("manifest.json")).unwrap()).unwrap();
    for name in std::iter::once("legacy.zip").chain(
        manifest["valid"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap()),
    ) {
        assert_eq!(
            backup::read(&std::fs::read(root.join(name)).unwrap()).unwrap(),
            recipes,
            "{name}"
        );
    }
    for name in [
        "python-setup-0-0.zip",
        "python-setup-8-0.zip",
        "python-setup-8-1.zip",
    ] {
        let (_, setup) = backup::read_with_setup(&std::fs::read(root.join(name)).unwrap()).unwrap();
        let setup = setup.unwrap();
        assert_eq!(setup.categories[0].name, "Farm stand");
        assert_eq!(setup.classify("large white onions"), "produce");
    }
    for name in manifest["invalid"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap())
    {
        assert!(
            backup::read(&std::fs::read(root.join(name)).unwrap()).is_err(),
            "accepted {name}"
        );
    }
    let mut output = recipes;
    output[0].content.ingredients[0].amount =
        cookdex_core::recipe::Amount::parse_exact("1 1/2–2").unwrap();
    let bytes = backup::write(&output).unwrap();
    assert_eq!(backup::read(&bytes).unwrap(), output);
    std::fs::write(root.join("rust.zip"), bytes).unwrap();
    let mut setup = cookdex_core::shopping_categories::Setup::default();
    setup.categories.reverse();
    setup.remember("white onion", "frozen").unwrap();
    let with_setup = backup::write_with_setup(&output, Some(&setup)).unwrap();
    assert_eq!(
        backup::read_with_setup(&with_setup).unwrap(),
        (output.clone(), Some(setup))
    );
    std::fs::write(root.join("rust-setup.zip"), with_setup).unwrap();
    std::fs::write(
        root.join("expected-rust.json"),
        serde_json::to_vec(&output).unwrap(),
    )
    .unwrap();
    println!(
        "A3 ZIP: legacy and setup STORE/DEFLATE/descriptor imports, hostile rejection, range/setup roundtrip PASS."
    );
}
