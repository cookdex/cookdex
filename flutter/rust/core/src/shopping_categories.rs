//! Offline aisle classification and device-local category preferences.
use crate::services::{Error, Result};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashSet};

pub const OTHER: &str = "other";
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Category {
    pub id: String,
    pub name: String,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Setup {
    pub categories: Vec<Category>,
    pub placements: BTreeMap<String, String>,
}
impl Default for Setup {
    fn default() -> Self {
        Self {
            categories: [
                ("produce", "Produce"),
                ("meat", "Meat & seafood"),
                ("dairy", "Dairy & eggs"),
                ("bakery", "Bakery"),
                ("pantry", "Pantry"),
                ("canned", "Canned goods"),
                ("spices", "Spices & seasonings"),
                ("frozen", "Frozen"),
                ("beverages", "Beverages"),
                ("household", "Household"),
                (OTHER, "Other"),
            ]
            .into_iter()
            .map(|(id, name)| Category {
                id: id.into(),
                name: name.into(),
            })
            .collect(),
            placements: BTreeMap::new(),
        }
    }
}
impl Setup {
    pub fn validate(&self) -> Result<()> {
        if self.categories.is_empty()
            || self.categories.len() > 200
            || self.placements.len() > 10000
        {
            return Err(Error::Limit);
        }
        let mut ids = HashSet::new();
        let mut names = HashSet::new();
        for c in &self.categories {
            if c.id.is_empty()
                || c.id.len() > 100
                || !ids.insert(c.id.as_str())
                || c.name.trim().is_empty()
                || c.name.chars().count() > 100
                || !names.insert(c.name.trim().to_lowercase())
            {
                return Err(Error::InvalidData);
            }
        }
        if !ids.contains(OTHER) {
            return Err(Error::InvalidData);
        }
        for (name, id) in &self.placements {
            if name.is_empty()
                || name.len() > 20000
                || normalize(name) != *name
                || !ids.contains(id.as_str())
            {
                return Err(Error::InvalidData);
            }
        }
        if serde_json::to_vec(self)
            .map_err(|_| Error::InvalidData)?
            .len()
            > crate::backup::MAX_SETUP_BYTES
        {
            return Err(Error::Limit);
        }
        Ok(())
    }
    pub fn contains(&self, id: &str) -> bool {
        self.categories.iter().any(|c| c.id == id)
    }
    pub fn classify(&self, name: &str) -> String {
        let key = normalize(name);
        let mut best = (0usize, 0usize, false, OTHER);
        for (id, phrase) in VOCABULARY.iter() {
            if contains_phrase(&key, phrase) {
                let score = (phrase.split_whitespace().count(), phrase.len(), false, *id);
                if score.0 > best.0 || (score.0 == best.0 && score.1 > best.1) {
                    best = score;
                }
            }
        }
        // Storage words change the aisle even when the base ingredient is known.
        // A complete remembered phrase can still override this default.
        let modifier = key.split_whitespace().find_map(|w| match w {
            "frozen" => Some("frozen"),
            "canned" => Some("canned"),
            "dried" => Some("pantry"),
            _ => None,
        });
        if let Some(id) = modifier.filter(|_| best.0 < key.split_whitespace().count()) {
            best = (key.split_whitespace().count(), key.len(), false, id);
        }
        for (phrase, id) in &self.placements {
            if contains_phrase(&key, phrase) {
                let score = (
                    phrase.split_whitespace().count(),
                    phrase.len(),
                    true,
                    id.as_str(),
                );
                if (score.0, score.1, score.2) >= (best.0, best.1, best.2) {
                    best = score;
                }
            }
        }
        if self.contains(best.3) {
            best.3.into()
        } else {
            OTHER.into()
        }
    }
    pub fn remember(&mut self, name: &str, id: &str) -> Result<()> {
        let key = normalize(name);
        if !self.contains(id) || key.is_empty() {
            return Err(Error::InvalidData);
        }
        self.placements.insert(key, id.into());
        self.validate()
    }
}
fn contains_phrase(name: &str, phrase: &str) -> bool {
    format!(" {name} ").contains(&format!(" {phrase} "))
}
fn singular(word: &str) -> String {
    match word {
        "tomatoes" => "tomato",
        "potatoes" => "potato",
        "mangoes" => "mango",
        "cookies" => "cookie",
        "brownies" => "brownie",
        "leaves" => "leaf",
        "loaves" => "loaf",
        "knives" => "knife",
        "berries" => "berry",
        "cherries" => "cherry",
        "strawberries" => "strawberry",
        "blueberries" => "blueberry",
        "raspberries" => "raspberry",
        "blackberries" => "blackberry",
        "cranberries" => "cranberry",
        "chilies" | "chiles" | "chile" => "chili",
        "catsup" => "ketchup",
        "hamb" | "hamburger" => "ground beef",
        "scallion" | "scallions" => "green onion",
        "aubergine" | "aubergines" => "eggplant",
        "courgette" | "courgettes" => "zucchini",
        "coriander" => "cilantro",
        "rocket" => "arugula",
        "garbanzo" => "chickpea",
        "sazon" => "sazón",
        "molasses" | "couscous" | "asparagus" | "hummus" | "swiss" | "watercress" | "grass"
        | "lemongrass" | "citrus" => word,
        _ => {
            return if word.len() > 4 && word.ends_with("ies") {
                format!("{}y", &word[..word.len() - 3])
            } else if ["ches", "shes", "xes", "sses", "zes"]
                .iter()
                .any(|suffix| word.ends_with(suffix))
            {
                singular(&word[..word.len() - 2])
            } else if word.len() > 3 && word.ends_with('s') && !word.ends_with("ss") {
                singular(&word[..word.len() - 1])
            } else {
                word.into()
            };
        }
    }
    .into()
}
/// Canonical plain name for both built-ins and remembered placements. No fuzzy matching.
pub fn normalize(name: &str) -> String {
    let lower = name.trim().to_lowercase();
    let quantity_words = [
        "a", "an", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "half",
    ];
    let has_quantity = lower.chars().next().is_some_and(|c| c.is_numeric())
        || lower
            .split_whitespace()
            .next()
            .is_some_and(|w| quantity_words.contains(&w));
    // Storage form affects the aisle even when written in a parenthetical note.
    let all_words = lower
        .split(|c: char| !c.is_alphabetic())
        .collect::<Vec<_>>();
    let modifiers = ["frozen", "canned", "dried"]
        .into_iter()
        .filter(|w| all_words.contains(w))
        .collect::<Vec<_>>();
    let mut plain = String::new();
    let mut depth = 0u32;
    for c in lower.chars() {
        if c == '(' || c == '[' {
            depth += 1;
            continue;
        }
        if c == ')' || c == ']' {
            depth = depth.saturating_sub(1);
            continue;
        }
        if depth > 0 {
            continue;
        }
        if c == ',' || c == ';' {
            break;
        }
        if c.is_alphabetic() {
            plain.push(c);
        } else {
            plain.push(' ');
        }
    }
    let plain = plain.split_whitespace().collect::<Vec<_>>().join(" ");
    let plain = plain
        .replace("gr pepper", "green pepper")
        .replace("gr beef", "ground beef")
        .replace("low sodium", " ")
        .replace("reduced sodium", " ")
        .replace("low fat", " ")
        .replace("fat free", " ")
        .replace("all purpose", " ")
        .replace("half and half", "halfandhalf")
        .replace("half half", "halfandhalf");
    let garlic_measure = has_quantity && plain.split_whitespace().any(|w| w == "garlic");
    let base = plain
        .split_whitespace()
        .filter(|w| {
            !modifiers.contains(w)
                && !(garlic_measure && ["clove", "cloves"].contains(w))
                && !(has_quantity
                    && (quantity_words.contains(w) || ["c", "t", "tb", "tbs"].contains(w)))
                && ![
                    "small",
                    "medium",
                    "large",
                    "med",
                    "lg",
                    "extra",
                    "fresh",
                    "freshly",
                    "lukewarm",
                    "room",
                    "temperature",
                    "as",
                    "needed",
                    "organic",
                    "boneless",
                    "skinless",
                    "unsalted",
                    "salted",
                    "lean",
                    "percent",
                    "chopped",
                    "diced",
                    "minced",
                    "sliced",
                    "grated",
                    "shredded",
                    "crushed",
                    "peeled",
                    "seeded",
                    "cored",
                    "trimmed",
                    "rinsed",
                    "drained",
                    "softened",
                    "melted",
                    "divided",
                    "optional",
                    "finely",
                    "coarsely",
                    "roughly",
                    "thinly",
                    "thickly",
                    "warm",
                    "hot",
                    "cold",
                    "boiling",
                    "cubed",
                    "beaten",
                    "sifted",
                    "packed",
                    "heaping",
                    "level",
                    "cup",
                    "cups",
                    "tbsp",
                    "tsp",
                    "tablespoon",
                    "tablespoons",
                    "teaspoon",
                    "teaspoons",
                    "lb",
                    "lbs",
                    "pound",
                    "pounds",
                    "oz",
                    "ounce",
                    "ounces",
                    "g",
                    "kg",
                    "ml",
                    "l",
                    "gram",
                    "grams",
                    "kilogram",
                    "kilograms",
                    "liter",
                    "liters",
                    "litre",
                    "litres",
                    "can",
                    "cans",
                    "package",
                    "packages",
                    "pkg",
                    "bunch",
                    "bunches",
                    "slice",
                    "slices",
                    "pinch",
                    "to",
                    "taste",
                    "of",
                ]
                .contains(w)
        })
        .map(singular)
        .collect::<Vec<_>>()
        .join(" ")
        .replace("halfandhalf", "half and half");
    modifiers
        .into_iter()
        .chain(std::iter::once(base.as_str()))
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}
pub fn recipe_omitted(name: &str) -> bool {
    matches!(
        normalize(name).as_str(),
        "water"
            | "ice"
            | "ice cube"
            | "ice water"
            | "tap water"
            | "filtered water"
            | "distilled water"
    )
}

/// Deliberately finite base vocabulary, with compound exceptions taking priority.
pub const INGREDIENTS: &[(&str, &str)] = &[
    (
        "produce",
        "apple|apricot|artichoke|arugula|asparagus|avocado|banana|basil|bean sprout|beet|bell pepper|blackberry|blueberry|bok choy|broccoli|brussels sprout|butternut squash|cabbage|cantaloupe|carrot|cauliflower|celery|chard|cherry|chili|chive|cilantro|coconut|collard|corn|cranberry|cucumber|date|dill|eggplant|endive|fennel|fig|garlic|ginger|grape|grapefruit|green bean|green onion|green pepper|guava|jalapeno|jalapeño|jicama|kale|kiwi|leek|lemon|lemongrass|lettuce|lime|mango|melon|mint|mushroom|mustard green|nectarine|okra|olive|onion|orange|papaya|parsley|parsnip|passion fruit|peach|pear|pea|persimmon|pineapple|plantain|plum|pomegranate|potato|pumpkin|radish|raspberry|rhubarb|romaine|rosemary|rutabaga|sage|shallot|snow pea|spinach|sprout|squash|strawberry|sweet potato|tangerine|tarragon|thyme|tomatillo|tomato|turnip|watercress|watermelon|yam|zucchini",
    ),
    (
        "meat",
        "bacon|beef|brisket|chicken|chicken breast|chicken thigh|clam|cod|crab|duck|fish|ground beef|ground chicken|ground pork|ground turkey|ham|halibut|hot dog|lamb|liver|lobster|mussel|oyster|pancetta|pepperoni|pork|pork chop|prosciutto|rib|salami|salmon|sausage|scallop|shrimp|steak|tilapia|trout|tuna|turkey|veal|venison",
    ),
    (
        "dairy",
        "butter|buttermilk|cheddar|cheese|cottage cheese|cream|cream cheese|creme fraiche|crème fraîche|egg|egg white|feta|ghee|goat cheese|gouda|half and half|heavy cream|kefir|margarine|mascarpone|milk|mozzarella|parmesan|provolone|ricotta|sour cream|swiss cheese|whipping cream|yogurt|yoghurt|velveeta|queso fresco",
    ),
    (
        "bakery",
        "bagel|baguette|bread|brioche|bun|ciabatta|corn tortilla|croissant|english muffin|flatbread|flour tortilla|focaccia|naan|pita|roll|rye bread|sourdough|tortilla",
    ),
    (
        "pantry",
        "almond|almond butter|almond flour|baking chocolate|baking powder|baking soda|barley|bean|bisquick|black bean|bread crumb|breadcrumb|broth|brown rice|brown sugar|buckwheat|bulgur|cake mix|canola oil|cashew|cereal|chicken broth|chicken stock|chickpea|chocolate|chocolate chip|cocoa|coconut flour|coconut oil|coconut milk|coffee creamer|confectioner sugar|corn syrup|cornmeal|cornstarch|couscous|cracker|crisco|dijon mustard|dry yeast|elbow macaroni|evaporated milk|farro|fish sauce|flour|gelatin|granola|grit|hazelnut|honey|hot sauce|icing sugar|jam|jelly|ketchup|kidney bean|lasagna|lentil|macadamia|macaroni|maple syrup|marshmallow|mayonnaise|millet|molasses|mustard|noodle|nut|nut butter|oat|oatmeal|olive oil|orzo|oyster sauce|panko|pasta|peanut|peanut butter|peanut oil|pecan|penne|pickle|pine nut|pinto bean|pistachio|polenta|popcorn|powdered sugar|preserve|pretzel|prune|quinoa|raisin|ramen|red wine vinegar|rice|rice flour|rice noodle|rice vinegar|rolled oat|salsa|sesame oil|shortening|soy sauce|spaghetti|stock|sugar|sunflower oil|sweetened condensed milk|syrup|tahini|tapioca|teriyaki sauce|tomato sauce|vegetable broth|vegetable oil|vegetable stock|vinegar|walnut|white rice|white wine vinegar|whole wheat flour|worcestershire sauce|yeast|balsamic vinegar|barbecue sauce|bbq sauce|caper|sun dried tomato",
    ),
    (
        "canned",
        "applesauce|baked bean|canned bean|canned corn|canned tomato|canned tuna|condensed soup|cream of mushroom soup|cream of chicken soup|pumpkin puree|refried bean|rotel|sardine|tomato paste|tomato puree|tomato purée|water chestnut",
    ),
    (
        "spices",
        "allspice|anise|bay leaf|black pepper|bouillon|cardamom|cayenne|cayenne pepper|celery salt|celery seed|chili flake|chili powder|chinese five spice|cinnamon|clove|cumin|curry powder|dried basil|dried dill|dried oregano|dried parsley|dried rosemary|dried thyme|fennel seed|garam masala|garlic powder|garlic salt|ground cinnamon|ground coriander|ground ginger|italian seasoning|kosher salt|lemon pepper|mustard powder|mustard seed|nutmeg|onion powder|oregano|paprika|pepper|peppercorn|poultry seasoning|red pepper flake|saffron|salt|sazón|seasoning|sesame seed|smoked paprika|star anise|taco seasoning|turmeric|vanilla|vanilla extract|white pepper",
    ),
    (
        "frozen",
        "frozen vegetable|frozen pea|frozen corn|frozen berry|ice cream|puff pastry|phyllo|pie crust|pizza dough|hash brown|tater tot|french fry|sorbet",
    ),
    (
        "beverages",
        "water|ice|apple juice|beer|black tea|bottled water|coffee|cola|cranberry juice|ginger ale|grape juice|green tea|juice|lemonade|orange juice|red wine|rum|seltzer|soda|sparkling water|tea|tonic water|vodka|whiskey|white wine|wine",
    ),
    (
        "household",
        "aluminum foil|aluminium foil|baking paper|bleach|cling film|detergent|dish soap|dishwasher tablet|foil|freezer bag|garbage bag|kitchen towel|laundry detergent|napkin|paper towel|parchment|parchment paper|plastic wrap|soap|sponge|tissue|toilet paper|toothpaste|trash bag|wax paper|zip bag",
    ),
];

static VOCABULARY: std::sync::LazyLock<Vec<(&'static str, String)>> =
    std::sync::LazyLock::new(|| {
        INGREDIENTS
            .iter()
            .flat_map(|(id, words)| words.split('|').map(move |word| (*id, normalize(word))))
            .filter(|(_, word)| !word.is_empty())
            .collect()
    });
