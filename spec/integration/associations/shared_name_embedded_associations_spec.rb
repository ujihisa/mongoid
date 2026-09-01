# frozen_string_literal: true

require 'spec_helper'

module SharedNameEmbeddedAssociationsSpec
  class Section
    include Mongoid::Document

    field :content

    embedded_in :parent, polymorphic: true
  end

  class Group
    include Mongoid::Document

    embedded_in :root
    embeds_many :sections, class_name: 'SharedNameEmbeddedAssociationsSpec::Section', store_as: :sections
  end

  class Root
    include Mongoid::Document

    embeds_many :sections, class_name: 'SharedNameEmbeddedAssociationsSpec::Section', store_as: :sections
    embeds_one :group, class_name: 'SharedNameEmbeddedAssociationsSpec::Group'
  end
end

RSpec.describe 'embedded associations with the same stored name' do
  let!(:root) do
    group = SharedNameEmbeddedAssociationsSpec::Group.new
    group.attributes = {
      sections: [ { content: 'group-original' } ]
    }
    root = SharedNameEmbeddedAssociationsSpec::Root.new
    root.sections = [ SharedNameEmbeddedAssociationsSpec::Section.new(content: 'root-original') ]
    root.group = group
    root.save!
    root
  end

  def stored_document
    SharedNameEmbeddedAssociationsSpec::Root.collection.find(_id: root.id).first
  end

  def contents_of(sections)
    sections.to_a.map { |section| section['content'] }
  end

  def reproduce_relative_delayed_atomic_path(document)
    # The current public assignment path records this key absolutely. Recreate
    # the relative buffer produced by the failing path to test the collision.
    document.sections.each do |section|
      section.new_record = false
      section.changed_attributes.clear
    end
    sets = document.delayed_atomic_sets.delete('group.sections')
    document._base.delayed_atomic_sets.delete('group.sections')
    document.delayed_atomic_sets['sections'] = sets
  end

  it 'does not merge parent and child sections on simultaneous assignment' do
    reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
    reloaded.attributes = {
      sections: [ { _id: reloaded.sections.first.id, content: 'root-updated' } ],
      group: { sections: [ { _id: reloaded.group.sections.first.id, content: 'group-updated' } ] }
    }
    reproduce_relative_delayed_atomic_path(reloaded.group)
    reloaded.save!

    stored = stored_document
    expect(contents_of(stored['sections'])).to eq [ 'root-updated' ]
    expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-updated' ]
  end

  it 'does not overwrite parent sections on child-only assignment' do
    reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
    reloaded.attributes = {
      group: { sections: [ { _id: reloaded.group.sections.first.id, content: 'group-only' } ] }
    }
    reproduce_relative_delayed_atomic_path(reloaded.group)
    reloaded.save!

    stored = stored_document
    expect(contents_of(stored['sections'])).to eq [ 'root-original' ]
    expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-only' ]
  end

  it 'does not copy child sections into an empty parent association' do
    reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
    reloaded.attributes = {
      sections: [],
      group: { sections: [ { _id: reloaded.group.sections.first.id, content: 'group-updated' } ] }
    }
    reproduce_relative_delayed_atomic_path(reloaded.group)
    reloaded.save!

    stored = stored_document
    expect(contents_of(stored['sections'] || [])).to eq []
    expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-updated' ]
  end
end
