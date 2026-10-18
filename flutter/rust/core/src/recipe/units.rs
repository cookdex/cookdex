//! Input-only unit normalization. Never called by stored recipe/ZIP readers.
use super::Amount;

pub fn normalize(input: &str) -> String {
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
        _ => return lower,
    }
    .into()
}

/// Sizes belong to the ingredient name, never the unit column.
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
    if plural {
        match unit {
            "cup" | "clove" | "can" => return format!("{unit}s"),
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
