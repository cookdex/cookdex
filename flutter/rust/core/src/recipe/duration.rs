//! Import/editor-save duration formatting; stored readers and ZIP transfers stay exact.
use super::{RecipeContent, rx};

pub fn readable(value: &str) -> String {
    let Some(c) =
        rx(r"(?i)^P(?:([0-9]+)D)?(?:T(?:([0-9]+)H)?(?:([0-9]+)M)?(?:([0-9]+(?:\.[0-9]+)?)S)?)?$")
            .captures(value.trim())
    else {
        return readable_words(value).unwrap_or_else(|| value.into());
    };
    // A bare P/PT or a trailing T is not a complete duration.
    if c.iter().skip(1).all(|part| part.is_none())
        || (value.trim().to_ascii_uppercase().ends_with('T'))
    {
        return value.into();
    }
    let parts = ["day", "hr", "min", "sec"]
        .iter()
        .enumerate()
        .filter_map(|(i, unit)| {
            c.get(i + 1).map(|v| {
                format!(
                    "{} {unit}{}",
                    v.as_str(),
                    if i == 0 && v.as_str() != "1" { "s" } else { "" }
                )
            })
        })
        .collect::<Vec<_>>()
        .join(" ");
    // Never expand a valid bounded field beyond the metadata limit.
    if parts.encode_utf16().count() > 80 {
        value.into()
    } else {
        parts
    }
}

fn readable_words(value: &str) -> Option<String> {
    let token = rx(
        r"(?i)([0-9]+(?:\.[0-9]+)?)\s*(days?|d|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b",
    );
    let input = value.trim();
    let mut end = 0;
    let mut previous = 0;
    let mut parts = Vec::new();
    for c in token.captures_iter(input) {
        let whole = c.get(0)?;
        if !input[end..whole.start()].trim().is_empty() {
            return None;
        }
        let raw = c[2].to_ascii_lowercase();
        let (rank, unit) = match raw.chars().next()? {
            'd' => (1, if &c[1] == "1" { "day" } else { "days" }),
            'h' => (2, "hr"),
            'm' => (3, "min"),
            's' => (4, "sec"),
            _ => return None,
        };
        if rank <= previous {
            return None;
        }
        previous = rank;
        parts.push(format!("{} {unit}", &c[1]));
        end = whole.end();
    }
    if parts.is_empty() || !input[end..].trim().is_empty() {
        return None;
    }
    let result = parts.join(" ");
    (result.encode_utf16().count() <= 80).then_some(result)
}

pub fn normalize(content: &mut RecipeContent) {
    content.prep_time = readable(&content.prep_time);
    content.cook_time = readable(&content.cook_time);
    content.total_time = readable(&content.total_time);
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn readable_durations_leave_non_durations_intact() {
        for (source, expected) in [
            ("PT22M", "22 min"),
            ("PT1H30M", "1 hr 30 min"),
            ("P2DT3H", "2 days 3 hr"),
            ("P1D", "1 day"),
            ("PT0S", "0 sec"),
            ("PT1.5S", "1.5 sec"),
            ("  pt22m  ", "22 min"),
            ("PT", "PT"),
            ("P1DT", "P1DT"),
            ("PT22M extra", "PT22M extra"),
            ("about 30 min", "about 30 min"),
            (" 1 hr ", "1 hr"),
            ("1 hour 30 minutes", "1 hr 30 min"),
            ("45minutes", "45 min"),
            ("2 hours", "2 hr"),
            ("30 min, plus proof", "30 min, plus proof"),
            ("1-2 hours", "1-2 hours"),
            ("1 hour 2 hours", "1 hour 2 hours"),
        ] {
            assert_eq!(readable(source), expected);
        }
    }
}
