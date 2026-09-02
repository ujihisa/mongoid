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
    accepts_nested_attributes_for :sections
  end

  class Root
    include Mongoid::Document

    embeds_many :sections, class_name: 'SharedNameEmbeddedAssociationsSpec::Section', store_as: :sections
    embeds_one :group, class_name: 'SharedNameEmbeddedAssociationsSpec::Group'
    accepts_nested_attributes_for :sections
    accepts_nested_attributes_for :group
  end
end

module NewEmbeddedChildSpec
  class Member
    include Mongoid::Document

    field :name

    embedded_in :team
  end

  class Team
    include Mongoid::Document

    embedded_in :org
    embeds_many :members, class_name: 'NewEmbeddedChildSpec::Member'
    accepts_nested_attributes_for :members
  end

  class Org
    include Mongoid::Document

    field :title

    embeds_one :team, class_name: 'NewEmbeddedChildSpec::Team'
    accepts_nested_attributes_for :team
  end
end

RSpec.describe 'embedded associations' do
  context 'with the same stored name' do
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
      sections.to_a.map { |section| section.respond_to?(:content) ? section.content : section['content'] }
    end

    # The persisted root has no group, so attributes= builds the new nested group
    # while the root sections update is still pending.
    it 'does not merge a new child into the parent association' do
      reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
      reloaded.attributes = {
        sections: [ { _id: reloaded.sections.first.id, content: 'root-updated' } ],
        group: { sections: [ { content: 'group-new' } ] }
      }
      reloaded.save!

      stored = stored_document
      expect(contents_of(stored['sections'])).to eq [ 'root-updated' ]
      expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-new' ]
      expect(contents_of(reloaded.sections)).to eq [ 'root-updated' ]
      expect(contents_of(reloaded.group.sections)).to eq [ 'group-new' ]
    end

    it 'does not copy a new child into an empty parent association' do
      reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
      reloaded.attributes = {
        sections: [],
        group: { sections: [ { content: 'group-new' } ] }
      }
      reloaded.save!

      stored = stored_document
      expect(stored).not_to have_key('sections')
      expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-new' ]
      expect(reloaded.sections).to be_empty
      expect(contents_of(reloaded.group.sections)).to eq [ 'group-new' ]
    end

    it 'does not merge a new child when the parent association is unchanged' do
      reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
      reloaded.attributes = { group: { sections: [ { content: 'group-new' } ] } }
      reloaded.save!

      stored = stored_document
      expect(contents_of(stored['sections'])).to eq [ 'root-original' ]
      expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-new' ]
      expect(contents_of(reloaded.sections)).to eq [ 'root-original' ]
      expect(contents_of(reloaded.group.sections)).to eq [ 'group-new' ]
    end

    it 'updates an existing group and isolates a subsequently added group' do
      root.group = SharedNameEmbeddedAssociationsSpec::Group.new(
        sections: [ SharedNameEmbeddedAssociationsSpec::Section.new(content: 'group-original') ]
      )
      root.save!

      reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
      reloaded.attributes = {
        group: {
          _id: reloaded.group.id,
          sections: [ { _id: reloaded.group.sections.first.id, content: 'group-updated' } ]
        }
      }
      reloaded.save!

      stored = stored_document
      expect(contents_of(stored['sections'])).to eq [ 'root-original' ]
      expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-updated' ]
      expect(contents_of(reloaded.sections)).to eq [ 'root-original' ]
      expect(contents_of(reloaded.group.sections)).to eq [ 'group-updated' ]

      reloaded.attributes = {
        sections: [ { _id: reloaded.sections.first.id, content: 'root-updated' } ],
        group: { sections: [ { content: 'group-new' } ] }
      }
      reloaded.save!

      stored = stored_document
      expect(contents_of(stored['sections'])).to eq [ 'root-updated' ]
      expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-new' ]
      expect(contents_of(reloaded.sections)).to eq [ 'root-updated' ]
      expect(contents_of(reloaded.group.sections)).to eq [ 'group-new' ]
    end

    it 'does not merge a new child when updating the parent through nested attributes' do
      reloaded = SharedNameEmbeddedAssociationsSpec::Root.find(root.id)
      reloaded.attributes = {
        sections_attributes: {
          '0' => { _id: reloaded.sections.first.id, content: 'root-updated' }
        },
        group: { sections: [ { content: 'group-new' } ] }
      }
      reloaded.save!

      stored = stored_document
      expect(contents_of(stored['sections'])).to eq [ 'root-updated' ]
      expect(contents_of(stored.dig('group', 'sections'))).to eq [ 'group-new' ]
      expect(contents_of(reloaded.sections)).to eq [ 'root-updated' ]
      expect(contents_of(reloaded.group.sections)).to eq [ 'group-new' ]
    end
  end

  context 'when assigning a new embeds_one child with nested embeds_many' do
    let!(:org) { NewEmbeddedChildSpec::Org.create!(title: 't0') }

    it 'does not write the nested array as a root-level field' do
      reloaded = NewEmbeddedChildSpec::Org.find(org.id)
      reloaded.attributes = { title: 't1', team: { members: [ { name: 'm1' } ] } }
      reloaded.save!

      stored = NewEmbeddedChildSpec::Org.collection.find(_id: org.id).first
      expect(stored.keys).to match_array(%w[_id title team])
      expect(stored.dig('team', 'members').map { |member| member['name'] }).to eq [ 'm1' ]
    end

    it 'produces a single $set for the new child' do
      reloaded = NewEmbeddedChildSpec::Org.find(org.id)
      reloaded.attributes = { team: { members: [ { name: 'm1' } ] } }

      expect(reloaded.atomic_updates['$set'].keys).to eq [ 'team' ]
    end
  end
end
