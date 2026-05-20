require "./spec_helper"

describe Regex::Syntax do
  it "escapes regex meta characters like Rust" do
    Regex::Syntax.escape(%q(\.+*?()|[]{}^$#&-~)).should eq(%q(\\\.\+\*\?\(\)\|\[\]\{\}\^\$\#\&\-\~))
  end

  it "writes escaped regex meta characters into an io like Rust" do
    io = IO::Memory.new
    Regex::Syntax.escape_into(%q(a+b), io)
    io.to_s.should eq(%q(a\+b))
  end

  it "detects meta characters like Rust" do
    Regex::Syntax.meta_character?('?').should be_true
    Regex::Syntax.meta_character?('-').should be_true
    Regex::Syntax.meta_character?('&').should be_true
    Regex::Syntax.meta_character?('#').should be_true

    Regex::Syntax.meta_character?('%').should be_false
    Regex::Syntax.meta_character?('/').should be_false
    Regex::Syntax.meta_character?('!').should be_false
    Regex::Syntax.meta_character?('"').should be_false
    Regex::Syntax.meta_character?('e').should be_false
  end

  it "detects escapable characters like Rust" do
    Regex::Syntax.escapeable_character?('?').should be_true
    Regex::Syntax.escapeable_character?('-').should be_true
    Regex::Syntax.escapeable_character?('&').should be_true
    Regex::Syntax.escapeable_character?('#').should be_true
    Regex::Syntax.escapeable_character?('%').should be_true
    Regex::Syntax.escapeable_character?('/').should be_true
    Regex::Syntax.escapeable_character?('!').should be_true
    Regex::Syntax.escapeable_character?('"').should be_true

    Regex::Syntax.escapeable_character?('e').should be_false
    Regex::Syntax.escapeable_character?('<').should be_false
    Regex::Syntax.escapeable_character?('☃').should be_false
  end

  it "detects ascii word bytes like Rust" do
    Regex::Syntax.word_byte?('a'.ord.to_u8).should be_true
    Regex::Syntax.word_byte?('_'.ord.to_u8).should be_true
    Regex::Syntax.word_byte?('-'.ord.to_u8).should be_false
  end

  it "detects unicode word characters like Rust" do
    Regex::Syntax.word_character?('a').should be_true
    Regex::Syntax.word_character?('à').should be_true
    Regex::Syntax.word_character?('β').should be_true
    Regex::Syntax.word_character?('𑀑').should be_true
    Regex::Syntax.word_character?('𑠁').should be_true
    Regex::Syntax.word_character?('𖹀').should be_true
    Regex::Syntax.word_character?('-').should be_false
    Regex::Syntax.word_character?('☃').should be_false
  end

  it "exposes try_is_word_character through the always-enabled unicode surface" do
    Regex::Syntax.try_is_word_character('a').should be_true
    Regex::Syntax.try_is_word_character('☃').should be_false
  end
end
