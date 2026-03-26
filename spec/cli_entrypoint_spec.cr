require "../src/marten_importmap/cli"
require "./spec_helper"

describe "marten_importmap/cli entrypoint" do
  it "loads the main shard definitions when required first" do
    config = MartenImportmap::Configuration.new

    config.should be_a(MartenImportmap::Configuration)
  end
end
