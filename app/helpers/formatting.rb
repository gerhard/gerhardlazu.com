module Formatting
  def title(*words)
    words.compact.join(" ").concat(" - Gerhard Lazu").gsub(/^ - /, '')
  end
end