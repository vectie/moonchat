///|
// Common parsed JSON numbers are binary64 and Int decoding truncates. Inspect
// the original decimal token before converting, retaining exact integral forms.
fn slack_exact_ordinal(token : String) -> Int raise {
  if token.is_empty() || token[0] == '-' || token[0] < '0' || token[0] > '9' {
    fail("Slack ordinal must be an exact positive integer JSON number")
  }
  let digits = StringBuilder()
  let mut fraction = 0
  let mut after_dot = false
  let mut i = 0
  while i < token.length() && token[i] != 'e' && token[i] != 'E' {
    if token[i] == '.' {
      after_dot = true
    } else if token[i] >= '0' && token[i] <= '9' {
      digits.write_string(token[i:i + 1].to_owned())
      if after_dot {
        fraction += 1
      }
    } else {
      fail("Slack ordinal must be a JSON number")
    }
    i += 1
  }
  let mut exponent = 0
  if i < token.length() {
    i += 1
    let negative = i < token.length() && token[i] == '-'
    if i < token.length() && (token[i] == '-' || token[i] == '+') {
      i += 1
    }
    while i < token.length() {
      if token[i] < '0' || token[i] > '9' {
        fail("invalid Slack ordinal exponent")
      }
      if exponent > 1048576 {
        fail("Slack ordinal exponent is out of range")
      }
      exponent = exponent * 10 + token[i].to_int() - 48
      i += 1
    }
    if negative {
      exponent = -exponent
    }
  }
  let digits = digits.to_string()
  let mut first = 0
  let mut end = digits.length()
  while first < end && digits[first] == '0' {
    first += 1
  }
  if first == end {
    fail("Slack ordinal must be in 1..1000")
  }
  while end > first && digits[end - 1] == '0' {
    end -= 1
  }
  let scale = exponent - fraction + digits.length() - end
  if scale < 0 || end - first + scale > 4 {
    fail("Slack ordinal must be an exact integer in 1..1000")
  }
  let mut result = 0
  for j in first..<end {
    result = result * 10 + digits[j].to_int() - 48
  }
  for _ in 0..<scale {
    result *= 10
  }
  if result < 1 || result > 1000 {
    fail("Slack ordinal must be in 1..1000")
  }
  let decoded : Int = @json.from_json(@json.parse(token))
  if decoded != result {
    fail("Slack ordinal decoder disagrees with its exact decimal token")
  }
  result
}

///|
// Only after complete syntax and duplicate-key validation. Decoded object names
// include escaped ordinal spellings; strings used as notes remain inert.
fn slack_validate_ordinal_tokens(text : String) -> Unit raise {
  let mut i = 0
  while i < text.length() {
    if text[i] != '"' {
      i += 1
      continue
    }
    let start = i
    i += 1
    while i < text.length() && text[i] != '"' {
      if text[i] == '\\' {
        i += 2
      } else {
        i += 1
      }
    }
    i += 1
    let end = i
    while i < text.length() &&
          (
            text[i] == ' ' ||
            text[i] == '\t' ||
            text[i] == '\r' ||
            text[i] == '\n'
          ) {
      i += 1
    }
    if i < text.length() && text[i] == ':' {
      let name : String = @json.from_json(@json.parse(text[start:end]))
      if name == "ordinal" {
        i += 1
        while i < text.length() &&
              (
                text[i] == ' ' ||
                text[i] == '\t' ||
                text[i] == '\r' ||
                text[i] == '\n'
              ) {
          i += 1
        }
        let number_start = i
        while i < text.length() &&
              text[i] != ',' &&
              text[i] != '}' &&
              text[i] != ']' &&
              text[i] != ' ' &&
              text[i] != '\t' &&
              text[i] != '\r' &&
              text[i] != '\n' {
          i += 1
        }
        ignore(slack_exact_ordinal(text[number_start:i].to_owned()))
      }
    }
  }
}
