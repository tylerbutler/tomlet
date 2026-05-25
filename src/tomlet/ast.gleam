import gleam/option.{type Option}

pub type Trivia {
  Trivia(text: String)
}

pub type Table {
  Table(entries: List(Entry), header: Option(Header))
}

pub type Header {
  Header(key: Key, kind: HeaderKind, trivia: Trivia)
}

pub type HeaderKind {
  StandardTable
  ArrayOfTablesHeader
}

pub type Entry {
  KeyValue(leading: Trivia, key: Key, value: Value, trailing: Trivia)
  TableHeader(header: Header)
  Comment(text: String)
  BlankLine
}

pub type Key {
  Key(segments: List(KeySegment))
}

pub type KeySegment {
  BareKeySegment(text: String)
  QuotedKeySegment(value: String, source_text: String)
}

pub type Value {
  Int(value: Int, source_text: String)
  Float(value: Float, source_text: String)
  SpecialFloat(value: SpecialFloat, source_text: String)
  Bool(value: Bool, source_text: String)
  String(value: String, style: StringStyle, source_text: String)
  Date(source_text: String)
  Time(source_text: String)
  DateTime(source_text: String)
  Array(items: List(ArrayItem), source_text: String)
  InlineTable(entries: List(InlineTableEntry), source_text: String)
  ArrayOfTables(items: List(Table))
}

pub type SpecialFloat {
  PositiveInfinity
  NegativeInfinity
  NotANumber
}

pub type StringStyle {
  BasicString
  LiteralString
  MultiBasicString
  MultiLiteralString
}

pub type ArrayItem {
  ArrayItem(leading: Trivia, value: Value, trailing: Trivia)
}

pub type InlineTableEntry {
  InlineTableEntry(leading: Trivia, key: Key, value: Value, trailing: Trivia)
}
