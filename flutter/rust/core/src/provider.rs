//! Provider transforms and retry policy. Transport/secure platform adapters are
//! injected; these functions never discover credentials, log bodies, or save.
use crate::{
    recipe::{self, Recipe},
    services::{Error, Operation, Result, now},
};
use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::{Value, json};
pub const REQUEST_LIMIT: usize = 16 * 1024 * 1024;
pub const RESPONSE_LIMIT: usize = 2 * 1024 * 1024;
pub const PHOTO_BASE64_LIMIT: usize = 12 * 1024 * 1024;
pub const INSTRUCTION: &str = include_str!("import_rules.txt");
pub const MAX_OUTPUT_TOKENS: u32 = 65_536;
const JSON_OUTPUT: &str = "Return JSON with every schema field. Set status to ok when any title, ingredients or steps can be extracted; otherwise use unreadable, not_a_recipe or retrieval_failed and give a short reason. Always return the status and reason fields. Use empty strings/arrays for absent fields. Set aiGuessedFields to every guessed nonempty servings, totalTime or tags field (shown as AI guess). Set aiGuessedSteps to the zero-based indices of EVERY step whose wording you wrote (shown as AI-written), including steps based on source facts or expanded from fragments. Do not mark verbatim copied steps or source-provided fields; unit-abbreviation normalization alone does not make a copied step AI-written.";
pub fn json_prompt(mode: &Mode, photos: bool, tags: &[String]) -> String {
    let mode_rules = if *mode == Mode::UrlRecipe {
        "Read only the supplied downloaded recipe text. Do not fetch source links."
    } else if photos {
        "Read the selected photos together in their supplied order. If they are unreadable, report unreadable with the reason."
    } else {
        "Read the supplied recipe text. If it is unreadable, report unreadable; if it contains no recipe, report not_a_recipe. Give a short reason."
    };
    format!(
        "{INSTRUCTION}\n{mode_rules}\n{JSON_OUTPUT}\nAllowed tags: {}",
        serde_json::to_string(tags).unwrap()
    )
}
pub fn copy_prompt(tags: &[String]) -> String {
    format!(
        "{INSTRUCTION}\nRead the text, link or photos I supply. For a link, read the linked page and use its final redirected URL.\n{}\nAllowed tags: {}",
        include_str!("copy_output.txt"),
        serde_json::to_string(tags).unwrap()
    )
}
pub const STARTER_TAGS: &[&str] = &[
    "breakfast",
    "lunch",
    "dinner",
    "dessert",
    "snack",
    "side",
    "appetizer",
    "drink",
    "sauce",
    "bread",
    "soup",
    "salad",
    "chicken",
    "beef",
    "pork",
    "seafood",
    "vegetarian",
    "quick",
    "baking",
    "slow cooker",
];

#[derive(Clone, Debug, Default, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiReview {
    #[serde(default)]
    pub ai_guessed_fields: Vec<String>,
    #[serde(default)]
    pub ai_guessed_steps: Vec<u32>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Mode {
    Recipe,
    UrlRecipe,
}
#[derive(Clone)]
pub struct Photo {
    pub mime_type: String,
    pub bytes: Vec<u8>,
}
#[derive(Clone)]
pub struct Input {
    pub text: String,
    pub source: String,
    pub target_title: String,
    pub photos: Vec<Photo>,
    pub mode: Mode,
    pub existing_tags: Vec<String>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Output {
    Recipe(Recipe),
}
fn object(properties: Value) -> Value {
    let required = properties
        .as_object()
        .unwrap()
        .keys()
        .cloned()
        .collect::<Vec<_>>();
    json!({"type":"object","properties":properties,"required":required,"additionalProperties":false})
}
/// Shape-only provider schema; C2 validators independently enforce all bounds.
pub fn schema(_mode: &Mode) -> Value {
    let string = json!({"type":"string"});
    let ingredients = json!({"type":"array","items":object(json!({"amount":string,"unit":string,"name":string,"prepNote":string,"section":string,"optional":{"type":"boolean"}}))});
    let list = json!({"type":"array","items":string});
    object(
        json!({"status":{"type":"string","enum":["ok","unreadable","not_a_recipe","retrieval_failed"]},"reason":string,"title":string,"description":string,"servings":string,"prepTime":string,"cookTime":string,"totalTime":string,"source":string,"notes":string,"tags":list,"steps":list,"ingredients":ingredients,"aiGuessedFields":{"type":"array","items":{"type":"string","enum":["servings","totalTime","tags"]}},"aiGuessedSteps":{"type":"array","items":{"type":"integer","minimum":0}}}),
    )
}
pub fn request(input: &Input, model: &str, retry: bool) -> Result<Vec<u8>> {
    request_with_problems(
        input,
        model,
        if retry {
            Some("The previous reply was malformed. Return a complete recipe response.")
        } else {
            None
        },
    )
}
pub fn request_with_problems(
    input: &Input,
    model: &str,
    problems: Option<&str>,
) -> Result<Vec<u8>> {
    if model.is_empty()
        || model.len() > 120
        || !model
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-._".contains(&b))
    {
        return Err(Error::Credentials);
    }
    if input.text.len() > recipe::MAX_INPUT_BYTES
        || input.photos.len() > 8
        || input.source.len() > 2000
        || input.target_title.len() > 640
    {
        return Err(Error::Limit);
    }
    if input.text.trim().is_empty() && input.photos.is_empty() && input.mode != Mode::UrlRecipe {
        return Err(Error::Validation);
    }
    if !input.source.is_empty() && !recipe::model::safe_source(&input.source) {
        return Err(Error::Validation);
    }
    // Remote URL tools cannot enforce the app's HTTPS policy on every hop.
    // Links must be downloaded by the checked host fetcher and sent as Recipe text.
    if input.mode == Mode::UrlRecipe {
        return Err(Error::Validation);
    }
    let mut parts = vec![
        json!({"type":"text","text":json!({"text":input.text,"source":input.source,"targetTitle":input.target_title,"allowedTags":allowed_tags(input)}).to_string()}),
    ];
    let mut size = input.text.len();
    let mut photo_size = 0;
    for photo in &input.photos {
        let encoded = photo.bytes.len().div_ceil(3) * 4;
        size += encoded;
        photo_size += encoded;
        if size >= REQUEST_LIMIT || photo_size > PHOTO_BASE64_LIMIT {
            return Err(Error::Limit);
        }
        if photo.mime_type != "image/jpeg"
            || !photo.bytes.starts_with(&[0xff, 0xd8, 0xff])
            || !photo.bytes.ends_with(&[0xff, 0xd9])
        {
            return Err(Error::Validation);
        }
        parts.push(
            json!({"type":"image","mime_type":"image/jpeg","data":STANDARD.encode(&photo.bytes)}),
        );
    }
    let mut instruction = json_prompt(&input.mode, !input.photos.is_empty(), &allowed_tags(input));
    if let Some(problems) = problems {
        instruction.push_str(&format!("\nThe previous reply failed local validation: {}. Correct these specific problems and return a complete response.", safe_reason(problems)));
    }
    let mut payload = json!({"model":model,"input":parts,"system_instruction":instruction,"response_format":{"type":"text","mime_type":"application/json","schema":schema(&input.mode)},"generation_config":{"max_output_tokens":MAX_OUTPUT_TOKENS},"store":false});
    // Retain the tested existing baseline explicitly. Low did not improve the
    // round-2 matrix; regular Flash was unavailable. This is not a quality win.
    if model == "gemini-3.5-flash-lite" {
        payload["generation_config"]["thinking_level"] = json!("minimal");
    }
    let body = serde_json::to_vec(&payload).map_err(|_| Error::Validation)?;
    if body.len() >= REQUEST_LIMIT {
        return Err(Error::Limit);
    }
    Ok(body)
}
#[derive(Debug)]
pub struct ResponseProblem {
    pub message: String,
    pub retryable: bool,
}
fn problem(message: impl Into<String>, retryable: bool) -> ResponseProblem {
    ResponseProblem {
        message: message.into(),
        retryable,
    }
}
pub fn response_text(bytes: &[u8]) -> std::result::Result<String, ResponseProblem> {
    if bytes.len() > RESPONSE_LIMIT {
        return Err(problem(
            "Gemini's reply exceeded the response size limit.",
            false,
        ));
    }
    let value: Value = serde_json::from_slice(bytes).map_err(|e| {
        problem(
            format!("Gemini's response envelope was invalid JSON: {e}"),
            true,
        )
    })?;
    if value["status"] == "incomplete"
        || value["finish_reason"] == "MAX_TOKENS"
        || value["finish_reason"] == "max_output_tokens"
    {
        return Err(problem(
            "The reply was cut off because Gemini reached its output token limit. Try again with a shorter source.",
            true,
        ));
    }
    if value
        .get("status")
        .and_then(Value::as_str)
        .is_some_and(|s| s != "completed")
    {
        return Err(problem(
            failure_reason(bytes).unwrap_or_else(|| "Gemini did not complete the reply.".into()),
            false,
        ));
    }
    let text = model_text(&value)
        .map_err(|_| problem("Gemini's reply was missing its recipe text.", true))?;
    if text.trim().is_empty() {
        return Err(problem(
            "Nothing usable came back: no title, no ingredients and no steps.",
            true,
        ));
    }
    Ok(text)
}
pub fn validated_response(
    bytes: &[u8],
) -> std::result::Result<(Recipe, Vec<String>), ResponseProblem> {
    let text = response_text(bytes)?;
    let text = text
        .trim()
        .strip_prefix("```json")
        .or_else(|| text.trim().strip_prefix("```"))
        .and_then(|s| s.trim().strip_suffix("```"))
        .unwrap_or(text.trim());
    let written: Value = serde_json::from_str(text).map_err(|e| {
        problem(
            if e.is_eof() {
                "The reply was cut off before the recipe was complete.".into()
            } else {
                format!(
                    "Gemini's recipe reply was invalid JSON at line {}, column {}: {}",
                    e.line(),
                    e.column(),
                    e
                )
            },
            true,
        )
    })?;
    if let Some(status) = written["status"].as_str().filter(|s| *s != "ok") {
        let label = match status {
            "unreadable" => "Gemini could not read the recipe",
            "not_a_recipe" => "Gemini found no recipe in the supplied material",
            "retrieval_failed" => "Gemini could not retrieve the page",
            _ => "Gemini reported an unknown recipe status",
        };
        // A non-ok status is a failure only if there is no usable recipe content.
        if super::recipe::repair::written(&written, &now()).is_err() {
            let reason = written["reason"]
                .as_str()
                .filter(|s| !s.trim().is_empty())
                .map(safe_reason)
                .unwrap_or_else(|| "No further reason was supplied.".into());
            return Err(problem(format!("{label}: {reason}"), false));
        }
    }
    let (recipe, mut warnings) =
        recipe::repair::written(&written, &now()).map_err(|e| problem(e.to_string(), true))?;
    if written["status"] != "ok" {
        warnings.push("Gemini omitted or reported an inconsistent status; usable recipe fields were kept for review.".into());
    }
    Ok((recipe, warnings))
}
pub fn response(bytes: &[u8], _mode: &Mode) -> Result<Output> {
    validated_response(bytes)
        .map(|(r, _)| Output::Recipe(r))
        .map_err(|_| Error::Provider)
}
fn model_text(value: &Value) -> Result<String> {
    Ok(value["steps"]
        .as_array()
        .ok_or(Error::Provider)?
        .iter()
        .filter(|s| s["type"] == "model_output")
        .filter_map(|s| s["content"].as_array())
        .flatten()
        .filter(|p| p["type"] == "text")
        .filter_map(|p| p["text"].as_str())
        .collect::<Vec<_>>()
        .join("\n"))
}
pub fn allowed_tags(input: &Input) -> Vec<String> {
    let mut tags: Vec<String> = STARTER_TAGS.iter().map(|s| s.to_string()).collect();
    for tag in &input.existing_tags {
        let tag = tag.trim().to_lowercase();
        if !tag.is_empty() && tag.encode_utf16().count() <= 300 && !tags.contains(&tag) {
            tags.push(tag);
        }
    }
    tags
}
/// Review metadata is transient and never enters schema-1 recipe storage/ZIPs.
pub fn review_response(bytes: &[u8], input: &Input, recipe: &mut Recipe) -> Result<AiReview> {
    let value: Value = serde_json::from_slice(bytes).map_err(|_| Error::Provider)?;
    let text = model_text(&value)?;
    let text = text
        .trim()
        .strip_prefix("```json")
        .or_else(|| text.trim().strip_prefix("```"))
        .and_then(|s| s.trim().strip_suffix("```"))
        .unwrap_or(text.trim());
    let written: Value = serde_json::from_str(text).map_err(|_| Error::Provider)?;
    let mut review: AiReview = serde_json::from_value(written.clone()).unwrap_or_default();
    let allowed = allowed_tags(input);
    recipe.content.tags.retain(|tag| allowed.contains(tag));
    recipe.content.tags.truncate(3);
    review
        .ai_guessed_fields
        .retain(|field| match field.as_str() {
            "servings" => !recipe.content.servings.is_empty(),
            "totalTime" => !recipe.content.total_time.is_empty(),
            "tags" => !recipe.content.tags.is_empty(),
            _ => false,
        });
    review.ai_guessed_fields.sort();
    review.ai_guessed_fields.dedup();
    let marked = review.ai_guessed_steps.clone();
    review.ai_guessed_steps = written["steps"]
        .as_array()
        .into_iter()
        .flatten()
        .take(recipe::MAX_ITEMS)
        .enumerate()
        .filter(|(_, step)| step.as_str().is_some_and(|s| !s.trim().is_empty()))
        .enumerate()
        .filter(|(_, (original, _))| marked.contains(&(*original as u32)))
        .map(|(normalized, _)| normalized as u32)
        .collect();
    review.ai_guessed_steps.sort();
    review.ai_guessed_steps.dedup();
    Ok(review)
}
/// Only structured provider diagnostics, never a dump of the request/response.
pub fn failure_reason(bytes: &[u8]) -> Option<String> {
    if bytes.len() > RESPONSE_LIMIT {
        return None;
    }
    let value: Value = serde_json::from_slice(bytes).ok()?;
    let reason = value["error"]["message"]
        .as_str()
        .or_else(|| value["error"]["status"].as_str());
    if let Some(reason) = reason {
        return Some(safe_reason(reason));
    }
    for step in value["steps"].as_array().into_iter().flatten() {
        if step["type"] == "url_context_result" {
            for result in step["result"].as_array().into_iter().flatten() {
                if let Some(status) = result["status"].as_str().filter(|s| *s != "success") {
                    return Some(format!(
                        "Gemini URL context: {}",
                        safe_reason(
                            result["error"]
                                .as_str()
                                .or_else(|| result["message"].as_str())
                                .unwrap_or(status)
                        )
                    ));
                }
            }
        }
    }
    if let Some(status) = value["status"].as_str().filter(|s| *s != "completed") {
        return Some(format!("Gemini response: {}", safe_reason(status)));
    }
    if let Ok(text) = model_text(&value) {
        if !text.trim().is_empty() && serde_json::from_str::<Value>(&text).is_err() {
            return Some(format!("Gemini: {}", safe_reason(&text)));
        }
        if let Ok(result) = serde_json::from_str::<Value>(&text) {
            if let Some(reason) = result["error"]
                .as_str()
                .or_else(|| result["error"]["message"].as_str())
            {
                return Some(format!("Gemini: {}", safe_reason(reason)));
            }
        }
    }
    value["status"]
        .as_str()
        .filter(|s| *s != "completed")
        .map(|s| format!("Gemini response: {}", safe_reason(s)))
}
fn safe_reason(reason: &str) -> String {
    let bounded: String = reason
        .chars()
        .filter(|c| !c.is_control())
        .take(600)
        .collect();
    recipe::rx(r"AIza[0-9A-Za-z_-]+")
        .replace_all(&bounded, "[redacted key]")
        .into_owned()
}
/// URL fallback must prove that the requested page was actually retrieved.
pub fn verify_url_response(bytes: &[u8], input: &Input) -> Result<()> {
    if input.mode != Mode::UrlRecipe {
        return Ok(());
    }
    if bytes.len() > RESPONSE_LIMIT {
        return Err(Error::Limit);
    }
    let value: Value = serde_json::from_slice(bytes).map_err(|_| Error::Provider)?;
    let success = value["steps"].as_array().is_some_and(|steps| {
        steps.iter().any(|step| {
            step["type"] == "url_context_result"
                && step["is_error"] != true
                && step["result"].as_array().is_some_and(|results| {
                    results.iter().any(|r| {
                        r["status"] == "success" && r["url"].as_str() == Some(input.source.as_str())
                    })
                })
        })
    });
    if success {
        Ok(())
    } else {
        Err(Error::UrlRetrieval)
    }
}
pub fn status_error(status: u16, bytes: &[u8]) -> Error {
    if status == 429 {
        return Error::Quota;
    }
    if [401, 403, 404].contains(&status) {
        return Error::Credentials;
    }
    if status == 400 && bytes.len() <= RESPONSE_LIMIT {
        if let Ok(value) = serde_json::from_slice::<Value>(bytes) {
            if value["error"]["details"]
                .as_array()
                .is_some_and(|ds| ds.iter().any(|d| d["reason"] == "API_KEY_INVALID"))
            {
                return Error::Credentials;
            }
        }
    }
    Error::Transport
}
pub trait Transport {
    fn send(&self, body: &[u8]) -> Result<(u16, Vec<u8>)>;
}
/// Exactly one malformed-result retry; transport/auth/quota/limits never retry.
pub fn extract(
    input: &Input,
    model: &str,
    transport: &impl Transport,
    operation: &Operation,
) -> Result<Output> {
    for attempt in 0..2 {
        operation.check()?;
        let body = request(input, model, attempt == 1)?;
        let (status, bytes) = transport.send(&body)?;
        operation.check()?;
        if !(200..300).contains(&status) {
            return Err(status_error(status, &bytes));
        }
        verify_url_response(&bytes, input)?;
        match response(&bytes, &input.mode) {
            Err(Error::Provider) if attempt == 0 => (),
            result => return result,
        }
    }
    Err(Error::Provider)
}
