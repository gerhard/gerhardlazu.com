require File.expand_path(File.dirname(__FILE__) + '/../spec_helper.rb')

describe "Formatting" do
  subject { Class.new.extend(Formatting) }

  its(:title) { should eql "Gerhard Lazu" }
end
