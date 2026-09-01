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
    root = SharedNameEmbeddedAssociationsSpec::Root.new
    root.sections = [ SharedNameEmbeddedAssociationsSpec::Section.new(content: 'root-original') ]
    root.save!
    root
  end

  def stored_document
    SharedNameEmbeddedAssociationsSpec::Root.collection.find(_id: root.id).first
  end

  def contents_of(sections)
    sections.to_a.map { |section| section['content'] }
  end

  # A persisted root without a group is important here: attributes= builds the
  # new nested group while the root sections update is still pending. This
  # fails before delayed atomic paths are normalized because the new child's
  # sections are merged into the root sections array.
  it 'does not merge a new child into the parent association' do
    root_without_group = SharedNameEmbeddedAssociationsSpec::Root.new
    root_without_group.sections = [ SharedNameEmbeddedAssociationsSpec::Section.new(content: 'root-original') ]
    root_without_group.save!

    reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root_without_group.id)
    reloaded.attributes = {
      sections: [ { _id: reloaded.sections.first.id, content: 'root-updated' } ],
      group: { sections: [ { content: 'group-new' } ] }
    }
    reloaded.save!

    stored = SharedNameEmbeddedAssociationsSpec::Root.collection.find(_id: root_without_group.id).first
    expect(contents_of(stored['sections'])).to eq [ 'root-updated' ]
    expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-new' ]
  end

  it 'does not copy a new child into an empty parent association' do
    reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
    reloaded.attributes = {
      sections: [],
      group: { sections: [ { content: 'group-new' } ] }
    }
    reloaded.save!

    stored = stored_document
    expect(contents_of(stored['sections'] || [])).to eq []
    expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-new' ]
  end

  it 'does not merge a new child when retaining the parent content' do
    reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
    reloaded.attributes = {
      sections: [ { _id: reloaded.sections.first.id, content: 'root-original' } ],
      group: { sections: [ { content: 'group-new' } ] }
    }
    reloaded.save!

    stored = stored_document
    expect(contents_of(stored['sections'])).to eq [ 'root-original' ]
    expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-new' ]
  end
end
