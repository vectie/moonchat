///|
// A syntax-validated source reader retains numeric tokens, including finite
// decimals too precise for Double. Editing one value must not round another.
priv struct ReviewJsonReader {
  chars : Array[Char]
  mut position : Int
}

///|
fn ReviewJsonReader::space(self : ReviewJsonReader) -> Unit {
  while self.position < self.chars.length() && [' ', '\t', '\r', '\n'].contains(self.chars[self.position]) {
    self.position += 1
  }
}

///|
fn ReviewJsonReader::string(self : ReviewJsonReader) -> String raise {
  let token = StringBuilder()
  token.write_char('"')
  self.position += 1
  while self.position < self.chars.length() {
    let ch = self.chars[self.position]
    token.write_char(ch)
    self.position += 1
    if ch == '\\' {
      token.write_char(self.chars[self.position])
      self.position += 1
    } else if ch == '"' { break }
  }
  guard @json.parse(token.to_string()) is String(value) else { fail("invalid JSON string") }
  value
}

///|
fn ReviewJsonReader::value(self : ReviewJsonReader) -> Json raise {
  self.space()
  match self.chars[self.position] {
    '{' => {
      self.position += 1
      self.space()
      let fields : Map[String, Json] = {}
      if self.chars[self.position] != '}' {
        while true {
          let key = self.string()
          if fields.contains(key) { fail("JSON artifact contains a duplicate object key") }
          self.space()
          self.position += 1
          fields[key] = self.value()
          self.space()
          if self.chars[self.position] == '}' { break }
          self.position += 1
          self.space()
        }
      }
      self.position += 1
      Json::object(fields)
    }
    '[' => {
      self.position += 1
      self.space()
      let values : Array[Json] = []
      if self.chars[self.position] != ']' {
        while true {
          values.push(self.value())
          self.space()
          if self.chars[self.position] == ']' { break }
          self.position += 1
        }
      }
      self.position += 1
      Json::array(values)
    }
    '"' => Json::string(self.string())
    _ => {
      let token = StringBuilder()
      while self.position < self.chars.length() && ![' ', '\t', '\r', '\n', ',', '}', ']'].contains(self.chars[self.position]) {
        token.write_char(self.chars[self.position])
        self.position += 1
      }
      let spelling = token.to_string()
      match @json.parse(spelling) {
        Number(number, ..) => Json::number(number, repr=spelling)
        value => value
      }
    }
  }
}

///|
fn review_parse_exact_json(text : String) -> Json raise {
  ignore(@json.parse(text, max_nesting_depth=64))
  let reader : ReviewJsonReader = {chars: text.iter().collect(), position: 0}
  reader.value()
}
