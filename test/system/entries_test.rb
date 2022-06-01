require "application_system_test_case"

class EntriesTest < ApplicationSystemTestCase
  setup do
    @entry = entries(:one)
  end

  test "should create entry" do
    visit person_url(people(:Kathryn))
    click_on "Add heats", match: :first

    within page.find('h2', text: 'CLOSED CATEGORY').sibling('div') do
      check "Tango"
      check "Rumba"
    end

    click_on "Create Entry"

    assert_text "2 heats successfully created"
    click_on "Back"
  end

  test "should update Entry - addition" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Entries').sibling('tbody') do
      find('td', text: 'Full Silver').hover
      click_on "Edit"
    end

    within page.find('h2', text: 'CLOSED CATEGORY').sibling('div') do
      check "Tango"
      check "Rumba"
    end

    click_on "Update Entry"

    assert_text "2 heats added"
    click_on "Back"
  end

  test "should update Entry - modification" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Entries').sibling('tbody') do
      find('td', text: 'Full Silver').hover
      click_on "Edit"
    end

    within page.find('h2', text: 'CLOSED CATEGORY').sibling('div') do
      check "Tango"
    end

    within page.find('h2', text: 'OPEN CATEGORY').sibling('div') do
      uncheck "Tango"
    end

    click_on "Update Entry"

    assert_text "2 heats changed"
    click_on "Back"
  end

  test "should update Entry - deletion" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Entries').sibling('tbody') do
      find('td', text: 'Full Silver').hover
      click_on "Edit"
    end

    within page.find('h2', text: 'OPEN CATEGORY').sibling('div') do
      uncheck "Tango"
    end

    click_on "Update Entry"

    assert_text "1 heat removed"
    click_on "Back"
  end

  test "should destroy Entry" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Entries').sibling('tbody') do
      find('td', text: 'Full Silver').hover
      click_on "Edit"
    end

    click_on "Remove this entry", match: :first
    page.accept_alert

    assert_text "4 heats successfully removed"
  end
end
