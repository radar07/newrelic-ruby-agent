# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sampler'
require 'new_relic/agent/vm'

module NewRelic
  module Agent
    module Samplers
      class VMSampler < Sampler
        GC_RUNS_METRIC      = 'RubyVM/GC/runs'.freeze
        HEAP_LIVE_METRIC    = 'RubyVM/GC/heap_live'.freeze
        HEAP_FREE_METRIC    = 'RubyVM/GC/heap_free'.freeze
        THREAD_COUNT_METRIC = 'RubyVM/Threads/all'.freeze
        OBJECT_ALLOCATIONS_METRIC     = 'RubyVM/GC/total_allocated_object'.freeze
        MAJOR_GC_METRIC               = 'RubyVM/GC/major_gc_count'.freeze
        MINOR_GC_METRIC               = 'RubyVM/GC/minor_gc_count'.freeze
        METHOD_INVALIDATIONS_METRIC   = 'RubyVM/CacheInvalidations/method'.freeze
        CONSTANT_INVALIDATIONS_METRIC = 'RubyVM/CacheInvalidations/constant'.freeze

        attr_reader :transaction_count

        def initialize
          super :vm
          @lock = Mutex.new
          @transaction_count = 0
          @last_snapshot = take_snapshot
        end

        def take_snapshot
          NewRelic::Agent::VM.snapshot
        end

        def setup_events(event_listener)
          event_listener.subscribe(:transaction_finished, &method(:on_transaction_finished))
        end

        def on_transaction_finished(*_)
          @lock.synchronize { @transaction_count += 1 }
        end

        def reset_transaction_count
          @lock.synchronize do
            old_count = @transaction_count
            @transaction_count = 0
            old_count
          end
        end

        def record_gc_runs_metric(snapshot, txn_count)
          if snapshot.gc_total_time || snapshot.gc_runs
            if snapshot.gc_total_time
              gc_time = snapshot.gc_total_time - @last_snapshot.gc_total_time
            end
            if snapshot.gc_runs
              gc_runs = snapshot.gc_runs - @last_snapshot.gc_runs
            end
            NewRelic::Agent.agent.stats_engine.record_metrics(GC_RUNS_METRIC) do |stats|
              stats.call_count           = txn_count
              stats.total_call_time      = gc_runs if gc_runs
              stats.total_exclusive_time = gc_time if gc_time
            end
          end
        end

        def record_delta(snapshot, key, metric, txn_count)
          value = snapshot.send(key)
          if value
            delta = value - @last_snapshot.send(key)
            NewRelic::Agent.agent.stats_engine.record_metrics(metric) do |stats|
              stats.call_count      = txn_count
              stats.total_call_time = delta
            end
          end
        end

        def record_heap_live_metric(snapshot)
          if snapshot.heap_live
            NewRelic::Agent.record_metric(HEAP_LIVE_METRIC, :count => snapshot.heap_live)
          end
        end

        def record_heap_free_metric(snapshot)
          if snapshot.heap_free
            NewRelic::Agent.record_metric(HEAP_FREE_METRIC, :count => snapshot.heap_free)
          end
        end

        def poll
          snap = take_snapshot
          tcount = reset_transaction_count

          record_gc_runs_metric(snap, tcount)
          record_delta(snap, :total_allocated_object, OBJECT_ALLOCATIONS_METRIC, tcount)
          record_delta(snap, :major_gc_count, MAJOR_GC_METRIC, tcount)
          record_delta(snap, :minor_gc_count, MINOR_GC_METRIC, tcount)
          record_delta(snap, :method_cache_invalidations, METHOD_INVALIDATIONS_METRIC, tcount)
          record_delta(snap, :constant_cache_invalidations, CONSTANT_INVALIDATIONS_METRIC, tcount)
          record_heap_live_metric(snap)
          record_heap_free_metric(snap)
          NewRelic::Agent.record_metric(THREAD_COUNT_METRIC, :count => snap.thread_count)

          @last_snapshot = snap
        end
      end
    end
  end
end