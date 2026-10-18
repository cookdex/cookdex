//! Exact temporary scaling; no recipe writes or input snapping.
use super::{Amount, Rational, Result, error, units};

/// Half-units keep the half-step choices exact across the bridge.
pub fn factor(scale: u32) -> Result<Rational> {
    if !(1..=10).contains(&scale) {
        return Err(error("Unknown recipe multiplier."));
    }
    Rational::new(scale as u128, 2)
}
pub fn amount(value: Amount, factor: Rational) -> Result<Amount> {
    let Some((low, high)) = value.bounds() else {
        return Ok(value);
    };
    let one = Rational::new(1, 1)?;
    Amount::range(low.convert(factor, one)?, high.convert(factor, one)?)
}
fn measured(value: Rational) -> bool {
    [1, 2, 3, 4, 8].contains(&value.denominator())
}
fn text(value: Amount, unit: &str) -> String {
    [value.text(), units::display(unit, value)]
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}
/// Prefer familiar measures, and keep an exact fraction if a ladder cannot express it.
pub fn quantity(value: Amount, unit: &str, scale: u32) -> Result<String> {
    let value = amount(value, factor(scale)?)?;
    if scale == 2 {
        return Ok(text(value, &units::normalize(unit)));
    }
    display_scaled(value, unit)
}
pub fn display_scaled(value: Amount, unit: &str) -> Result<String> {
    let key = units::normalize(unit);
    let Some((low, high)) = value.bounds() else {
        return Ok(text(value, &key));
    };
    let ladder: &[(&str, u128)] = match key.as_str() {
        "cup" | "tbsp" | "tsp" => &[("cup", 48), ("tbsp", 3), ("tsp", 1)],
        "lb" | "oz" => &[("lb", 16), ("oz", 1)],
        "kg" | "g" => &[("kg", 1000), ("g", 1)],
        "l" | "ml" => &[("l", 1000), ("ml", 1)],
        _ => return Ok(text(value, &key)),
    };
    let from = Rational::new(ladder.iter().find(|(u, _)| *u == key).unwrap().1, 1)?;
    for &(unit, size) in ladder {
        let to = Rational::new(size, 1)?;
        let a = low.convert(from, to)?;
        let b = high.convert(from, to)?;
        let large_enough = a.numerator() >= a.denominator()
            || (unit == "cup" && a.numerator() * 2 >= a.denominator())
            || unit == ladder.last().unwrap().0;
        if large_enough
            && measured(a)
            && measured(b)
            && !(unit == "tbsp" && (a.denominator() == 3 || b.denominator() == 3))
        {
            return Ok(text(Amount::range(a, b)?, unit));
        }
        if low == high && a.numerator() > a.denominator() && a.denominator() != 1 {
            let whole = a.numerator() / a.denominator();
            let rest = Rational::new(
                (a.numerator() % a.denominator()) as u128,
                a.denominator() as u128,
            )?;
            for &(small, small_size) in ladder.iter().filter(|(_, s)| *s < size) {
                let remainder = rest.convert(to, Rational::new(small_size, 1)?)?;
                if measured(remainder) && remainder.numerator() <= remainder.denominator() * 3 {
                    return Ok(format!(
                        "{} + {}",
                        text(Rational::new(whole as u128, 1)?.into(), unit),
                        text(remainder.into(), small)
                    ));
                }
            }
        }
    }
    Ok(text(value, &key))
}
pub fn servings(input: &str, scale: u32) -> Result<String> {
    let f = factor(scale)?;
    if scale == 2 {
        return Ok(input.into());
    }
    let n = super::amount::NUMBER_PATTERN;
    let re = regex::Regex::new(&format!(r"{n}(?:\s*(?:–|-|to)\s*{n})?")).unwrap();
    let Some(found) = re.find(input) else {
        return Ok(input.into());
    };
    let value = Amount::parse_exact(found.as_str())?;
    Ok(format!(
        "{}{}{}",
        &input[..found.start()],
        amount(value, f)?.text(),
        &input[found.end()..]
    ))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn all_half_step_multipliers_are_exact_and_bounded() {
        for scale in 1..=10 {
            assert_eq!(
                amount(Amount::parse_exact("2").unwrap(), factor(scale).unwrap())
                    .unwrap()
                    .text(),
                scale.to_string()
            );
        }
        assert!(factor(0).is_err());
        assert!(factor(11).is_err());
        assert_eq!(servings("5–6 servings", 9).unwrap(), "22 1/2–27 servings");
    }
    #[test]
    fn exact_ladders_ranges_and_counts() {
        for (input, unit, scale, expected) in [
            ("1/3", "cup", 4, "2/3 cup"),
            ("1/3", "cup", 5, "13 tbsp + 1 tsp"),
            ("3", "eggs", 3, "4 1/2 eggs"),
            ("1–2", "cup", 9, "4 1/2–9 cups"),
            ("8", "tbsp", 4, "1 cup"),
            ("3/4", "cup", 1, "6 tbsp"),
            ("1/3", "cup", 1, "2 tbsp + 2 tsp"),
            ("3", "", 1, "1 1/2"),
            ("2", "(14 oz) cans", 4, "4 (14 oz) cans"),
            ("8", "oz", 4, "1 lb"),
            ("500", "g", 4, "1 kg"),
            ("500", "ml", 4, "1 l"),
            ("1–2", "cup", 4, "2–4 cups"),
            ("", "", 4, ""),
            ("to taste", "", 1, "to taste"),
            ("1/5", "", 1, "1/10"),
        ] {
            assert_eq!(
                quantity(Amount::parse_exact(input).unwrap(), unit, scale).unwrap(),
                expected
            );
        }
        assert_eq!(
            servings("Makes 5–6 servings", 4).unwrap(),
            "Makes 10–12 servings"
        );
        assert_eq!(servings("Serves a crowd", 1).unwrap(), "Serves a crowd");
        assert_eq!(servings("12 tortillas", 4).unwrap(), "24 tortillas");
        assert_eq!(
            servings("Makes 12 tortillas", 4).unwrap(),
            "Makes 24 tortillas"
        );
        assert_eq!(servings("1 pint of salsa", 4).unwrap(), "2 pint of salsa");
    }
}
