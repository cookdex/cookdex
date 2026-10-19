//! Input-only unit normalization. Never called by stored recipe/ZIP readers.
use super::Amount;

pub fn normalize(input: &str) -> String {
    // Package sizes are user text, preserved on save and interchange.
    if package(input).is_some() {
        return input.trim().into();
    }
    let raw = input.trim().trim_end_matches('.');
    if raw == "T" {
        return "tbsp".into();
    }
    let lower = raw.to_lowercase();
    match lower.as_str() {
        "tb" | "tbs" | "tbsp" | "tablespoon" | "tablespoons" => "tbsp",
        "t" | "tsp" | "teaspoon" | "teaspoons" => "tsp",
        "c" | "cup" | "cups" => "cup",
        "oz" | "ounce" | "ounces" => "oz",
        "lb" | "lbs" | "pound" | "pounds" => "lb",
        "g" | "gram" | "grams" => "g",
        "kg" | "kilogram" | "kilograms" => "kg",
        "ml" | "milliliter" | "milliliters" | "millilitre" | "millilitres" => "ml",
        "l" | "liter" | "liters" | "litre" | "litres" => "l",
        "pinch" | "pinches" => "pinch",
        "clove" | "cloves" => "clove",
        "can" | "cans" => "can",
        "jar" | "jars" => "jar",
        "bottle" | "bottles" => "bottle",
        "box" | "boxes" => "box",
        "bag" | "bags" => "bag",
        "package" | "packages" => "package",
        _ => return lower,
    }
    .into()
}

/// Recognize only the supported container suffix after a nonempty parenthesized size.
/// The prefix is opaque: never parse, scale or convert a package's size.
pub fn package(input: &str) -> Option<(&str, &'static str)> {
    let raw = input.trim();
    if !raw.starts_with('(') {
        return None;
    }
    let end = raw.find(')')?;
    if raw[1..end].trim().is_empty() {
        return None;
    }
    let container = match raw[end + 1..].trim().to_lowercase().as_str() {
        "can" | "cans" => "can",
        "jar" | "jars" => "jar",
        "bottle" | "bottles" => "bottle",
        "box" | "boxes" => "box",
        "bag" | "bags" => "bag",
        "package" | "packages" => "package",
        _ => return None,
    };
    Some((&raw[..=end], container))
}

/// A comparison key only; stored sized-unit spelling stays untouched.
pub fn package_key(input: &str) -> Option<String> {
    package(input).map(|(size, container)| format!("{} {container}", size.to_lowercase()))
}

/// Import-only recovery of a singular sized container with an implicit count.
/// Require a physical size, a singular container and a nonempty product name.
pub fn implicit_package(input: &str) -> Option<(String, String)> {
    let captures = super::rx(r"(?i)^\s*([0-9]+(?:\.[0-9]+)?\s+(?:oz|ounces?|lb|pounds?|g|grams?|kg|kilograms?|ml|milliliters?|l|liters?))\s+(can|jar|bottle|box|bag|package)\s+(?:of\s+)?(.+?)\s*$")
        .captures(input)?;
    let size = &captures[1];
    let number = size.split_whitespace().next()?.parse::<f64>().ok()?;
    if number <= 0.0 || !number.is_finite() || captures[3].eq_ignore_ascii_case("of") {
        return None;
    }
    Some((
        format!("({size}) {}", captures[2].to_lowercase()),
        captures[3].to_string(),
    ))
}

/// Adjectival sizes belong to names; parenthesized container sizes stay in units.
pub fn normalize_ingredient(unit: &str, name: &str) -> (String, String) {
    let unit = normalize(unit);
    let size = match unit.as_str() {
        "small" => "small",
        "medium" | "med" => "medium",
        "large" | "lg" => "large",
        _ => return (unit, name.trim().into()),
    };
    let name = name.trim();
    let first = name
        .split_whitespace()
        .next()
        .unwrap_or("")
        .trim_end_matches('.')
        .to_lowercase();
    let already_present =
        first == size || (size == "medium" && first == "med") || (size == "large" && first == "lg");
    (
        String::new(),
        if already_present {
            name.into()
        } else {
            format!("{size} {name}").trim().into()
        },
    )
}

/// Recover only a complete recognized leading unit token, on editor save.
/// Callers require a quantity so names such as "can opener" stay intact.
pub fn leading_unit(name: &str) -> Option<(String, String)> {
    let name = name.trim();
    let (token, remainder) = name.split_once(char::is_whitespace)?;
    let unit = normalize(token);
    if remainder.trim().is_empty()
        || !matches!(
            unit.as_str(),
            "tbsp"
                | "tsp"
                | "cup"
                | "oz"
                | "lb"
                | "g"
                | "kg"
                | "ml"
                | "l"
                | "pinch"
                | "clove"
                | "can"
                | "jar"
                | "bottle"
                | "box"
                | "bag"
                | "package"
        )
    {
        return None;
    }
    Some((unit, remainder.trim().into()))
}

pub fn display(unit: &str, amount: Amount) -> String {
    let plural = amount
        .bounds()
        .is_some_and(|(_, upper)| upper.numerator() > upper.denominator());
    if let Some((size, container)) = package(unit) {
        let suffix = if plural {
            if container == "box" { "es" } else { "s" }
        } else {
            ""
        };
        return format!("{size} {container}{suffix}");
    }
    if plural {
        match unit {
            "cup" | "clove" | "slice" | "sprig" | "stalk" | "head" | "can" | "jar" | "bottle"
            | "bag" | "package" => {
                return format!("{unit}s");
            }
            "box" => return "boxes".into(),
            "bunch" => return "bunches".into(),
            "pinch" => return "pinches".into(),
            _ => (),
        }
    }
    unit.into()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn handwritten_case_is_significant() {
        for input in ["TB", "T", "Tbs", "Tbsp", "tablespoons", "TBSP."] {
            assert_eq!(normalize(input), "tbsp");
        }
        for input in ["t", "tsp.", "teaspoons"] {
            assert_eq!(normalize(input), "tsp");
        }
        for input in ["c", "C", "Cups"] {
            assert_eq!(normalize(input), "cup");
        }
        assert_eq!(normalize("lbs"), "lb");
        assert_eq!(normalize("ounces"), "oz");
        assert_eq!(display("clove", Amount::parse_new("2").unwrap()), "cloves");
        assert_eq!(display("cup", Amount::parse_new("1/2").unwrap()), "cup");
        assert_eq!(display("tbsp", Amount::parse_new("2").unwrap()), "tbsp");
    }
}
