require "test_helper"

class FilterTest < ActiveSupport::TestCase
  test "bubbles" do
    Current.set session: sessions(:david) do
      @new_bucket = accounts("37s").buckets.create! name: "Inaccessible Bucket"
      @new_bubble = @new_bucket.bubbles.create!
      @new_bubble.update!(stage: workflow_stages(:qa_triage))

      bubbles(:layout).capture Comment.new(body: "I hate haggis")
      bubbles(:logo).capture Comment.new(body: "I love haggis")
      bubbles(:logo).update(stage: workflow_stages(:qa_triage))
    end

    assert_not_includes users(:kevin).filters.new.bubbles, @new_bubble

    filter = users(:david).filters.new indexed_by: "most_discussed", assignee_ids: [ users(:jz).id ], tag_ids: [ tags(:mobile).id ]
    assert_equal [ bubbles(:layout) ], filter.bubbles

    filter = users(:david).filters.new creator_ids: [ users(:david).id ], tag_ids: [ tags(:mobile).id ]
    assert_equal [ bubbles(:layout) ], filter.bubbles

    filter = users(:david).filters.new stage_ids: [ workflow_stages(:qa_triage).id ]
    assert_equal [ bubbles(:logo), @new_bubble ], filter.bubbles

    filter = users(:david).filters.new assignment_status: "unassigned", bucket_ids: [ @new_bucket.id ]
    assert_equal [ @new_bubble ], filter.bubbles

    filter = users(:david).filters.new terms: [ "haggis" ]
    assert_equal bubbles(:logo, :layout).sort, filter.bubbles.sort

    filter = users(:david).filters.new terms: [ "haggis", "love" ]
    assert_equal [ bubbles(:logo) ], filter.bubbles

    filter = users(:david).filters.new indexed_by: "popped"
    assert_equal [ bubbles(:shipping) ], filter.bubbles
  end

  test "can't see bubbles in buckets that aren't accessible" do
    buckets(:writebook).update! all_access: false
    buckets(:writebook).accesses.revoke_from users(:david)

    assert_empty users(:david).filters.new(bucket_ids: [ buckets(:writebook).id ]).bubbles
  end

  test "remembering equivalent filters" do
    assert_difference "Filter.count", +1 do
      filter = users(:david).filters.remember(indexed_by: "most_active", assignment_status: "unassigned", tag_ids: [ tags(:mobile).id ])

      assert_changes "filter.reload.updated_at" do
        assert_equal filter, users(:david).filters.remember(tag_ids: [ tags(:mobile).id ], assignment_status: "unassigned")
      end
    end
  end

  test "remembering equivalent filters for different users" do
    assert_difference "Filter.count", +2 do
      users(:david).filters.remember(assignment_status: "unassigned", tag_ids: [ tags(:mobile).id ])
      users(:kevin).filters.remember(assignment_status: "unassigned", tag_ids: [ tags(:mobile).id ])
    end
  end

  test "turning into params" do
    filter = users(:david).filters.new indexed_by: "most_active", tag_ids: "", assignee_ids: [ users(:jz).id ], bucket_ids: [ buckets(:writebook).id ]
    expected = { assignee_ids: [ users(:jz).id ], bucket_ids: [ buckets(:writebook).id ] }
    assert_equal expected, filter.as_params
  end

  test "cacheability" do
    assert_not filters(:jz_assignments).cacheable?
    assert users(:david).filters.create!(bucket_ids: [ buckets(:writebook).id ]).cacheable?
  end

  test "terms" do
    assert_equal [], users(:david).filters.new.terms
    assert_equal [ "haggis" ], users(:david).filters.new(terms: [ "haggis" ]).terms
  end

  test "resource removal" do
    filter = users(:david).filters.create! tag_ids: [ tags(:mobile).id ], bucket_ids: [ buckets(:writebook).id ]

    assert_includes filter.as_params[:tag_ids], tags(:mobile).id
    assert_includes filter.tags, tags(:mobile)
    assert_includes filter.as_params[:bucket_ids], buckets(:writebook).id
    assert_includes filter.buckets, buckets(:writebook)

    assert_changes "filter.reload.updated_at" do
      tags(:mobile).destroy!
    end
    assert_nil filter.reload.as_params[:tag_ids]

    assert_changes "Filter.exists?(filter.id)" do
      buckets(:writebook).destroy!
    end
  end

  test "duplicate filters are removed after a resource is destroyed" do
    users(:david).filters.create! tag_ids: [ tags(:mobile).id ], bucket_ids: [ buckets(:writebook).id ]
    users(:david).filters.create! tag_ids: [ tags(:mobile).id, tags(:web).id ], bucket_ids: [ buckets(:writebook).id ]

    assert_difference "Filter.count", -1 do
      tags(:web).destroy!
    end
  end

  test "summary" do
    assert_equal "Most discussed, tagged #Mobile, and assigned to JZ ", filters(:jz_assignments).summary

    filters(:jz_assignments).update!(stages: workflow_stages(:qa_triage, :qa_in_progress))
    assert_equal "Most discussed, tagged #Mobile, assigned to JZ, and staged in Triage or In progress ", filters(:jz_assignments).summary

    filters(:jz_assignments).update!(stages: [], assignees: [], tags: [], buckets: [ buckets(:writebook) ])
    assert_equal "Most discussed in Writebook", filters(:jz_assignments).summary

    filters(:jz_assignments).update!(indexed_by: "stalled")
    assert_equal "Stalled in Writebook", filters(:jz_assignments).summary
  end

  test "params without a key-value pair" do
    filter = users(:david).filters.new indexed_by: "most_discussed", assignee_ids: [ users(:jz).id, users(:kevin).id ]

    expected = { indexed_by: "most_discussed", assignee_ids: [ users(:kevin).id ] }
    assert_equal expected, filter.as_params_without(:assignee_ids, users(:jz).id).to_h

    expected = { assignee_ids: [ users(:jz).id, users(:kevin).id ] }
    assert_equal expected, filter.as_params_without(:indexed_by, "most_discussed").to_h

    expected = { indexed_by: "most_discussed", assignee_ids: [ users(:jz).id, users(:kevin).id ] }
    assert_equal expected, filter.as_params_without(:indexed_by, "most_active").to_h

    expected = { indexed_by: "most_discussed", assignee_ids: [ users(:jz).id, users(:kevin).id ] }
    assert_equal expected, filter.as_params_without(:assignee_ids, users(:david).id).to_h
  end
end
