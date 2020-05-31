RSpec.describe "the project" do
  it "has no method without documentation" do
    expect(`./bin/methods-with-pending-documentation`).to eq ""
  end
end
