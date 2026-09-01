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
    embeds_many :sections,
                class_name: 'SharedNameEmbeddedAssociationsSpec::Section',
                store_as: :sections
  end

  class Root
    include Mongoid::Document

    embeds_many :sections,
                class_name: 'SharedNameEmbeddedAssociationsSpec::Section',
                store_as: :sections
    embeds_one :group, class_name: 'SharedNameEmbeddedAssociationsSpec::Group'
  end
end

RSpec.describe 'embedded associations with the same stored name' do
  let!(:root) do
    SharedNameEmbeddedAssociationsSpec::Root.create!(
      sections: [ SharedNameEmbeddedAssociationsSpec::Section.new(content: 'root-original') ],
      group: SharedNameEmbeddedAssociationsSpec::Group.new(
        sections: [ SharedNameEmbeddedAssociationsSpec::Section.new(content: 'group-original') ]
      )
    )
  end

  def stored_document
    SharedNameEmbeddedAssociationsSpec::Root.collection.find(_id: root.id).first
  end

  def contents_of(sections)
    sections.to_a.map { |section| section['content'] }
  end

  it 'does not merge parent and child sections on simultaneous assignment' do
    reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
    reloaded.attributes = {
      sections: [ { content: 'root-updated' } ],
      group: { sections: [ { content: 'group-updated' } ] }
    }
    reloaded.save!

    stored = stored_document
    expect(contents_of(stored['sections'])).to eq [ 'root-updated' ]
    expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-updated' ]
  end

  it 'does not overwrite parent sections on child-only assignment' do
    reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
    reloaded.attributes = {
      group: { sections: [ { content: 'group-only' } ] }
    }
    reloaded.save!

    stored = stored_document
    expect(contents_of(stored['sections'])).to eq [ 'root-original' ]
    expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-only' ]
  end

  it 'does not copy child sections into an empty parent association' do
    reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
    reloaded.attributes = {
      sections: [],
      group: { sections: [ { content: 'group-updated' } ] }
    }
    reloaded.save!

    stored = stored_document
    expect(contents_of(stored['sections'] || [])).to eq []
    expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-updated' ]
  end
end
