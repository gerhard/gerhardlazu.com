# Helper methods defined here can be accessed in any controller or view in the application

Gerhardlazu.helpers do
  def title(*words)
    words.compact.join(" ").concat(" - Gerhard Lazu").gsub(/^ - /, '')
  end
end