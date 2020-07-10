RSpec.describe "the project" do
  it "has no method without documentation" do
    expect(`./bin/methods-with-pending-documentation`).to eq ""
  end

  it "has no untested method" do
    expect(`bash -c 'comm -23 <(./bin/all-methods) <(./bin/tested-methods)'`).to eq ""
  end

  it "has no vestigial method" do
    expect(`./bin/vestigial-methods`).to eq ""
  end
end
