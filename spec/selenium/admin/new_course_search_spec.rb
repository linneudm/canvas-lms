#
# Copyright (C) 2015 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

require File.expand_path(File.dirname(__FILE__) + '/../common')

describe "new account course search" do
  include_context "in-process server selenium tests"

  before :once do
    account_model
    @account.enable_feature!(:course_user_search)
    account_admin_user(:account => @account, :active_all => true)
  end

  before do
    user_session(@user)
  end

  def get_rows
    ff('.courses-list [role=row]')
  end

  it "should not show the courses tab without permission" do
    @account.role_overrides.create! :role => admin_role, :permission => 'read_course_list', :enabled => false

    get "/accounts/#{@account.id}"

    expect(f(".react-tabs > ul")).to_not include_text("Courses")
  end

  it "should hide courses without enrollments if checked" do
    empty_course = course_factory(:account => @account, :course_name => "no enrollments")
    not_empty_course = course_factory(:account => @account, :course_name => "yess enrollments", :active_all => true)
    student_in_course(:course => not_empty_course, :active_all => true)

    get "/accounts/#{@account.id}"

    expect(get_rows.count).to eq 2

    cb = f('.course_search_bar input[type=checkbox]')
    move_to_click("label[for=#{cb['id']}]")

    expect(f('.courses-list')).not_to contain_jqcss('div[role=row]:nth-child(2)')

    rows = get_rows
    expect(rows.count).to eq 1
    expect(rows.first).to include_text(not_empty_course.name)
    expect(rows.first).to_not include_text(empty_course.name)
  end

  it "should paginate" do
    11.times do |x|
      course_factory(:account => @account, :course_name => "course_factory #{x + 1}")
    end

    get "/accounts/#{@account.id}"

    expect(get_rows.count).to eq 10

    f(".load_more").click
    wait_for_ajaximations

    expect(get_rows.count).to eq 11
    expect(f("#content")).not_to contain_css(".load_more")
  end

  it "should search by term" do
    term = @account.enrollment_terms.create!(:name => "some term")
    term_course = course_factory(:account => @account, :course_name => "term course_factory")
    term_course.enrollment_term = term
    term_course.save!

    other_course = course_factory(:account => @account, :course_name => "other course_factory")

    get "/accounts/#{@account.id}"

    click_option(".course_search_bar select", term.name)
    expect(f('.courses-list')).not_to contain_jqcss('div[role=row]:nth-child(2)')

    rows = get_rows
    expect(rows.count).to eq 1
    expect(rows.first).to include_text(term_course.name)
  end

  it "should search by name" do
    match_course = course_factory(:account => @account, :course_name => "course_factory with a search term")
    not_match_course = course_factory(:account => @account, :course_name => "diffrient cuorse")

    get "/accounts/#{@account.id}"

    f('.course_search_bar input[type=search]').send_keys('search')
    expect(f('.courses-list')).not_to contain_jqcss('div[role=row]:nth-child(2)')

    rows = get_rows
    expect(rows.count).to eq 1
    expect(rows.first).to include_text(match_course.name)
  end

  it "should show teachers" do
    course_factory(:account => @account)
    user_factory(:name => "some teacher")
    teacher_in_course(:course => @course, :user => @user)

    get "/accounts/#{@account.id}"

    user_link = get_rows.first.find("a.user_link")
    expect(user_link).to include_text(@user.name)
    expect(user_link['href']).to eq user_url(@user)
  end

  it "should show manageable roles in new enrollment dialog" do
    custom_name = 'Custom Student role'
    role = custom_student_role(custom_name, :account => @account)

    @account.role_overrides.create!(:permission => "manage_admin_users", :enabled => false, :role => admin_role)
    course_factory(:account => @account)

    get "/accounts/#{@account.id}"

    f('.courses-list [role=row] .addUserButton').click
    dialog = fj('.ui-dialog:visible')
    expect(dialog).to be_displayed
    role_options = dialog.find_elements(:css, '#role_id option')
    expect(role_options.map{|r| r.text}).to match_array(["Student", "Observer", custom_name])
  end

  it "should create a new course from the 'Add a New Course' dialog" do
    @account.enrollment_terms.create!(:name => "Test Enrollment Term")
    subaccount = @account.sub_accounts.create!(name: "Test Sub Account")

    get "/accounts/#{@account.id}"

    # fill out the form
    f('.selenium-spec-add-course-button').click
    dialog = f('.ReactModal__Content--canvas')
    expect(dialog).to be_displayed
    set_value(f('.name', dialog), 'Test Course Name')
    set_value(f('.course_code', dialog), 'TCN 101')
    click_option(".account_id", subaccount.to_param, :value)
    click_option(".enrollment_term_id", "Test Enrollment Term")
    submit_form(dialog)

    # make sure it got saved to db correctly
    new_course = Course.last
    expect(new_course.name).to eq('Test Course Name')
    expect(new_course.course_code).to eq('TCN 101')
    expect(new_course.account.name).to eq('Test Sub Account')
    expect(new_course.enrollment_term.name).to eq('Test Enrollment Term')

    # make sure it shows up on the page
    expect(f('.courses-list')).to include_text('Test Course Name')
  end
end
