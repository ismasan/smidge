# frozen_string_literal: true

RSpec.describe Smidge do
  it "has a version number" do
    expect(Smidge::VERSION).not_to be nil
  end

  specify '.to_method_name' do
    expect(Smidge.to_method_name("getUserInfo")).to eq "get_user_info"
    expect(Smidge.to_method_name("_getUser-Info")).to eq "get_user_info"
    expect(Smidge.to_method_name("get User Info")).to eq "get_user_info"
    expect(Smidge.to_method_name("get__user__--info")).to eq "get_user_info"
    expect(Smidge.to_method_name("GetUserInfo")).to eq "get_user_info"
  end
end
