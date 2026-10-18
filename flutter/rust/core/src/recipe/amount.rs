use super::{Result, bounded, error};
use serde::{Deserialize, Serialize};

pub const MAX_INTEGER: u64 = 9_007_199_254_740_991;
pub const NUMBER_PATTERN: &str =
    r"(?:[0-9]+\s+[0-9]+/[0-9]+|[0-9]+/[0-9]+|(?:[0-9]+\s*)?[¼½¾⅓⅔⅛⅜⅝⅞]|[0-9]+(?:\.[0-9]+)?)";
fn gcd(mut a: u128, mut b: u128) -> u128 {
    while b != 0 {
        (a, b) = (b, a % b);
    }
    a
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "Fraction")]
pub struct Rational {
    numerator: u64,
    denominator: u64,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Fraction {
    numerator: u64,
    denominator: u64,
}
impl TryFrom<Fraction> for Rational {
    type Error = super::RuleError;
    fn try_from(v: Fraction) -> Result<Self> {
        if v.numerator > MAX_INTEGER || v.denominator > MAX_INTEGER {
            return Err(error("Quantity exceeds exact integer bounds."));
        }
        Self::new(v.numerator as u128, v.denominator as u128)
    }
}
impl Rational {
    pub fn new(n: u128, d: u128) -> Result<Self> {
        if n == 0 || d == 0 {
            return Err(error("Use a positive quantity."));
        }
        let g = gcd(n, d);
        let (n, d) = (n / g, d / g);
        if n > MAX_INTEGER as u128 || d > MAX_INTEGER as u128 {
            return Err(error("Quantity exceeds exact integer bounds."));
        }
        Ok(Self {
            numerator: n as u64,
            denominator: d as u64,
        })
    }
    pub fn numerator(self) -> u64 {
        self.numerator
    }
    pub fn denominator(self) -> u64 {
        self.denominator
    }
    pub fn checked_add(self, rhs: Self) -> Result<Self> {
        Self::new(
            self.numerator as u128 * rhs.denominator as u128
                + rhs.numerator as u128 * self.denominator as u128,
            self.denominator as u128 * rhs.denominator as u128,
        )
    }
    /// Exact ratio conversion. Cancel all factors before multiplication.
    pub fn convert(self, from: Self, to: Self) -> Result<Self> {
        let mut ns = [
            self.numerator as u128,
            from.numerator as u128,
            to.denominator as u128,
        ];
        let mut ds = [
            self.denominator as u128,
            from.denominator as u128,
            to.numerator as u128,
        ];
        for n in &mut ns {
            for d in &mut ds {
                let g = gcd(*n, *d);
                *n /= g;
                *d /= g;
            }
        }
        let product = |xs: [u128; 3]| {
            xs.into_iter().try_fold(1u128, |a, b| {
                a.checked_mul(b).ok_or_else(|| error("Quantity overflow."))
            })
        };
        Self::new(product(ns)?, product(ds)?)
    }
    pub fn text(self) -> String {
        let (whole, rest) = (
            self.numerator / self.denominator,
            self.numerator % self.denominator,
        );
        if rest == 0 {
            whole.to_string()
        } else if whole == 0 {
            format!("{rest}/{}", self.denominator)
        } else {
            format!("{whole} {rest}/{}", self.denominator)
        }
    }
    /// Nearest absolute distance; equal distances choose the smaller candidate.
    /// Only the winner is tested against the candidate-relative 1% threshold.
    fn snap(self) -> Self {
        let whole = self.numerator / self.denominator;
        let mut best: Option<(Self, u128)> = None;
        for w in whole.saturating_sub(1)..=whole.saturating_add(1) {
            for (n, d) in [(0, 1), (1, 8), (1, 4), (1, 3), (1, 2), (2, 3), (3, 4)] {
                let Ok(c) = Self::new(w as u128 * d + n, d) else {
                    continue;
                };
                let diff = (self.numerator as u128 * c.denominator as u128)
                    .abs_diff(c.numerator as u128 * self.denominator as u128);
                if best.is_none_or(|(old, delta)| {
                    diff * (old.denominator as u128) < delta * c.denominator as u128
                }) {
                    best = Some((c, diff));
                }
            }
        }
        match best {
            Some((c, diff)) if diff * 100 <= self.denominator as u128 * c.numerator as u128 => c,
            _ => self,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_candidate_both_exact_boundaries_and_neighbors() {
        for whole in [0u128, 1] {
            for (n, d) in [(1, 8), (1, 4), (1, 3), (1, 2), (2, 3), (3, 4), (1, 1)] {
                let c = Rational::new(whole * d + n, d).unwrap();
                for side in [99u128, 101] {
                    let at = Rational::new((whole * d + n) * side, d * 100).unwrap();
                    assert_eq!(at.snap(), c, "at {at:?} for {c:?}");
                    let inside = Rational::new(
                        (whole * d + n) * side * 1000 + if side == 99 { 1 } else { 0 },
                        d * 100_000,
                    )
                    .unwrap();
                    let inside = if side == 101 {
                        Rational::new((whole * d + n) * side * 1000 - 1, d * 100_000).unwrap()
                    } else {
                        inside
                    };
                    assert_eq!(inside.snap(), c);
                    let outside = Rational::new(
                        (whole * d + n) * side * 1000 + if side == 101 { 1 } else { 0 },
                        d * 100_000,
                    )
                    .unwrap();
                    let outside = if side == 99 {
                        Rational::new((whole * d + n) * side * 1000 - 1, d * 100_000).unwrap()
                    } else {
                        outside
                    };
                    assert_eq!(outside.snap(), outside, "outside {outside:?} for {c:?}");
                }
            }
        }
    }
    #[test]
    fn nearest_ties_choose_lower_before_relative_threshold() {
        assert_eq!(Amount::parse_new("20.0625").unwrap().text(), "20");
        assert_eq!(Amount::parse_new("20.06250001").unwrap().text(), "20 1/8");
        assert_eq!(Amount::parse_new("0.0625").unwrap().text(), "1/16");
        assert_eq!(Amount::parse_new("0.999").unwrap().text(), "1");
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", try_from = "AmountWire")]
pub enum Amount {
    #[serde(rename = "number")]
    Rational {
        #[serde(flatten)]
        value: Rational,
    },
    #[serde(rename = "range")]
    Range { lower: Rational, upper: Rational },
    #[serde(rename = "toTaste")]
    ToTaste,
    #[serde(rename = "unspecified")]
    Unspecified,
}

#[derive(Deserialize)]
#[serde(tag = "kind", deny_unknown_fields)]
enum AmountWire {
    #[serde(rename = "number")]
    Number { numerator: u64, denominator: u64 },
    #[serde(rename = "range")]
    Range { lower: Rational, upper: Rational },
    #[serde(rename = "toTaste")]
    ToTaste {},
    #[serde(rename = "unspecified")]
    Unspecified {},
}
impl TryFrom<AmountWire> for Amount {
    type Error = super::RuleError;
    fn try_from(value: AmountWire) -> Result<Self> {
        match value {
            AmountWire::Range { lower, upper } => Self::range(lower, upper),
            AmountWire::Number {
                numerator,
                denominator,
            } => Ok(Rational::try_from(Fraction {
                numerator,
                denominator,
            })?
            .into()),
            AmountWire::ToTaste {} => Ok(Self::ToTaste),
            AmountWire::Unspecified {} => Ok(Self::Unspecified),
        }
    }
}
impl From<Rational> for Amount {
    fn from(value: Rational) -> Self {
        Self::Rational { value }
    }
}
/// Unchanged canonical values never pass through the new-input parser.
pub enum AmountInput<'a> {
    Unchanged(Amount),
    Written(&'a str),
}
impl Amount {
    pub fn range(lower: Rational, upper: Rational) -> Result<Self> {
        let order = (lower.numerator as u128 * upper.denominator as u128)
            .cmp(&(upper.numerator as u128 * lower.denominator as u128));
        match order {
            std::cmp::Ordering::Greater => Err(error(
                "The first amount must be no greater than the second amount.",
            )),
            std::cmp::Ordering::Equal => Ok(lower.into()),
            std::cmp::Ordering::Less => Ok(Self::Range { lower, upper }),
        }
    }
    pub fn bounds(self) -> Option<(Rational, Rational)> {
        match self {
            Self::Rational { value } => Some((value, value)),
            Self::Range { lower, upper } => Some((lower, upper)),
            _ => None,
        }
    }
    pub fn validate(self) -> Result<()> {
        if let Self::Range { lower, upper } = self {
            Self::range(lower, upper)?;
        }
        Ok(())
    }
    pub fn from_input(input: AmountInput<'_>) -> Result<Self> {
        match input {
            AmountInput::Unchanged(a) => Ok(a),
            AmountInput::Written(s) => Self::parse_new(s),
        }
    }
    pub fn text(self) -> String {
        match self {
            Self::Rational { value } => value.text(),
            Self::Range { lower, upper } => format!("{}–{}", lower.text(), upper.text()),
            Self::ToTaste => "to taste".into(),
            Self::Unspecified => String::new(),
        }
    }
    pub fn parse_exact(input: &str) -> Result<Self> {
        Self::parse(input, false)
    }
    pub fn parse_new(input: &str) -> Result<Self> {
        Self::parse(input, true)
    }
    fn parse(input: &str, snap: bool) -> Result<Self> {
        bounded(input, 2000)?;
        let mut text = input.trim().to_string();
        for (c, r) in [
            ('¼', "1/4"),
            ('½', "1/2"),
            ('¾', "3/4"),
            ('⅓', "1/3"),
            ('⅔', "2/3"),
            ('⅛', "1/8"),
            ('⅜', "3/8"),
            ('⅝', "5/8"),
            ('⅞', "7/8"),
        ] {
            text = text.replace(c, &format!(" {r}"));
        }
        let text = text.trim();
        if text.is_empty() {
            return Ok(Self::Unspecified);
        }
        if text.eq_ignore_ascii_case("to taste") {
            return Ok(Self::ToTaste);
        }
        static RANGE: std::sync::LazyLock<regex::Regex> = std::sync::LazyLock::new(|| {
            regex::Regex::new(&format!(
                r"(?i)^({NUMBER_PATTERN})\s*(?:–|-|\s+to\s+)\s*({NUMBER_PATTERN})$"
            ))
            .unwrap()
        });
        if let Some(c) = RANGE.captures(text) {
            // Parse both ends exactly first: snapping must not hide reversal.
            let (Self::Rational { value: lower }, Self::Rational { value: upper }) =
                (Self::parse(&c[1], false)?, Self::parse(&c[2], false)?)
            else {
                return Err(error("Use a number at each end of the range."));
            };
            Self::range(lower, upper)?;
            let (Self::Rational { value: lower }, Self::Rational { value: upper }) =
                (Self::parse(&c[1], snap)?, Self::parse(&c[2], snap)?)
            else {
                unreachable!()
            };
            return Self::range(lower, upper);
        }
        let integer = |s: &str| -> Result<u128> {
            if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
                return Err(error("Invalid quantity."));
            }
            s.parse().map_err(|_| error("Quantity overflow."))
        };
        if let Some((left, right)) = text.split_once('/') {
            let d = integer(right)?;
            let parts: Vec<_> = left.split_whitespace().collect();
            let (whole, n) = match parts.as_slice() {
                [n] => (0, integer(n)?),
                [w, n] => (integer(w)?, integer(n)?),
                _ => return Err(error("Invalid fraction.")),
            };
            let n = whole
                .checked_mul(d)
                .and_then(|w| w.checked_add(n))
                .ok_or_else(|| error("Quantity overflow."))?;
            return Ok(Rational::new(n, d)?.into());
        }
        let value = if let Some((whole, decimal)) = text.split_once('.') {
            integer(whole)?;
            integer(decimal)?;
            let decimal = decimal.trim_end_matches('0');
            let digits = format!("{}{}", whole.trim_start_matches('0'), decimal);
            let n = integer(if digits.is_empty() { "0" } else { &digits })?;
            let d = 10u128
                .checked_pow(decimal.len() as u32)
                .ok_or_else(|| error("Quantity overflow."))?;
            Rational::new(n, d)?
        } else {
            Rational::new(integer(text)?, 1)?
        };
        Ok(if snap && text.contains('.') {
            value.snap()
        } else {
            value
        }
        .into())
    }
}
