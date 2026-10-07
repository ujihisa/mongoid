Draft only. This text has not been submitted to Jira.

## Proposed summary

Prevent stale embedded update paths after sibling removal

## Description

Mongoid can write delayed updates to the wrong embedded document when an earlier sibling is removed from an `embeds_many` association before the parent is saved. The operation does not necessarily raise an error, so data in a different embedded document can be silently changed.

## Affected behavior

The issue reproduces when a saved embedded document is changed and a preceding sibling is removed before the same root document is saved. The affected changes include:

* Replacing a nested `embeds_many` association with `attributes=` and a non-empty array.
* Replacing a nested `embeds_many` association with `attributes=` and an empty array.
* Calling `remove_attribute` on an embedded document.

The sibling can be removed immediately with `delete`, or during save through nested attributes with `_destroy`.

## Reproduction

```ruby
class Leaf
  include Mongoid::Document
  field :name, type: String
  embedded_in :item
end

class Item
  include Mongoid::Document
  field :name, type: String
  field :label, type: String
  embedded_in :root
  embeds_many :leaves, class_name: 'Leaf'
end

class Root
  include Mongoid::Document
  embeds_many :items, class_name: 'Item'
end

# Persist a root whose items are a, b, c, with leaves [a1], [b1], [c1].
root = Root.find(id)
a, b, = root.items.to_a
b.attributes = { leaves: [Leaf.new(name: 'new')] }
root.items.delete(a)
root.save!
```

Expected result: `b.leaves` is `[new]` and `c.leaves` remains `[c1]`.

Actual result: the replacement path still refers to `items.1.leaves` after deleting `a` has shifted `b` to `items.0`. The update overwrites `c.leaves`; `b.leaves` remains `[b1, new]`.

The empty-array case leaves `b.leaves` unchanged and clears `c.leaves`. Calling `b.remove_attribute(:label)` before deleting `a` removes `c.label` instead of preserving it.

## Root cause

The association replacement code stores delayed atomic updates under the path computed at assignment time. `EmbedsMany::Proxy#reindex` changes `_index` after removing a sibling, but leaves cached atomic paths and delayed `$set`/`$unset` paths at their old positions. `remove_attribute` also stores the old positional path. When an empty association is replaced, the deferred unset document can retain an atomic-path cache that was computed before its parent moved.

## Proposed fix

When reindexing an embedded collection, capture the previous positions of the remaining documents and their descendants, update the indexes, clear the cached atomic paths, and rebase delayed path-keyed updates. Include documents held by delayed unsets when clearing caches so that empty nested associations also use their current parent position.

## Verification

Regression specs cover non-empty and empty `attributes=` replacements, `remove_attribute`, and sibling destruction through nested attributes. The reported data must remain unchanged in all non-target siblings.

## Related

* Reproduction and migration context: https://github.com/quipper/monorepo/issues/181010
* The `Atomic::Modifiers` conflicting-operator issue tracked separately in https://github.com/quipper/monorepo/issues/181078 is distinct; rebasing a stale positional path addresses the wrong-document write described here.
