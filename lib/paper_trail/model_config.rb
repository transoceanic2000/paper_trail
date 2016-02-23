require "active_support/core_ext"

module PaperTrail
  # Configures an ActiveRecord model, mostly at application boot time, but also
  # sometimes mid-request, with methods like enable/disable.
  class ModelConfig
    E_CANNOT_RECORD_AFTER_DESTROY = <<-STR.strip_heredoc.freeze
      paper_trail.on_destroy(:after) is incompatible with ActiveRecord's
      belongs_to_required_by_default and has no effect. Please use :before
      or disable belongs_to_required_by_default.
    STR

    def initialize(model_class)
      @model_class = model_class
    end

    # Switches PaperTrail off for this class.
    def disable
      ::PaperTrail.enabled_for_model(@model_class, false)
    end

    # Switches PaperTrail on for this class.
    def enable
      ::PaperTrail.enabled_for_model(@model_class, true)
    end

    def enabled?
      return false unless @model_class.include?(::PaperTrail::Model::InstanceMethods)
      ::PaperTrail.enabled_for_model?(@model_class)
    end

    # Adds a callback that records a version after a "create" event.
    def on_create
      @model_class.after_create :record_create, if: :save_version?
      return if @model_class.paper_trail_options[:on].include?(:create)
      @model_class.paper_trail_options[:on] << :create
    end

    # Adds a callback that records a version before or after a "destroy" event.
    def on_destroy(recording_order = "before")
      unless %w(after before).include?(recording_order.to_s)
        raise ArgumentError, 'recording order can only be "after" or "before"'
      end

      if recording_order == "after" && cannot_record_after_destroy?
        ::ActiveSupport::Deprecation.warn(E_CANNOT_RECORD_AFTER_DESTROY)
      end

      @model_class.send "#{recording_order}_destroy", :record_destroy, if: :save_version?

      return if @model_class.paper_trail_options[:on].include?(:destroy)
      @model_class.paper_trail_options[:on] << :destroy
    end

    # Adds a callback that records a version after an "update" event.
    def on_update
      @model_class.before_save :reset_timestamp_attrs_for_update_if_needed!, on: :update
      @model_class.after_update :record_update, if: :save_version?
      @model_class.after_update :clear_version_instance!
      return if @model_class.paper_trail_options[:on].include?(:update)
      @model_class.paper_trail_options[:on] << :update
    end

    def setup(options = {})
      # Lazily include the instance methods so we don't clutter up
      # any more ActiveRecord models than we have to.
      @model_class.send :include, ::PaperTrail::Model::InstanceMethods
      @model_class.send :extend, ::PaperTrail::AttributesSerialization

      @model_class.class_attribute :version_association_name
      @model_class.version_association_name = options[:version] || :version

      # The version this instance was reified from.
      @model_class.send :attr_accessor, @model_class.version_association_name

      @model_class.class_attribute :version_class_name
      @model_class.version_class_name = options[:class_name] || "PaperTrail::Version"

      @model_class.class_attribute :paper_trail_options

      @model_class.paper_trail_options = options.dup

      [:ignore, :skip, :only].each do |k|
        @model_class.paper_trail_options[k] = [@model_class.paper_trail_options[k]].
          flatten.
          compact.
          map { |attr| attr.is_a?(Hash) ? attr.stringify_keys : attr.to_s }
      end

      @model_class.paper_trail_options[:meta] ||= {}
      if @model_class.paper_trail_options[:save_changes].nil?
        @model_class.paper_trail_options[:save_changes] = true
      end

      @model_class.class_attribute :versions_association_name
      @model_class.versions_association_name = options[:versions] || :versions

      @model_class.send :attr_accessor, :paper_trail_event

      # `has_many` syntax for specifying order uses a lambda in Rails 4
      if ::ActiveRecord::VERSION::MAJOR >= 4
        @model_class.has_many(
          @model_class.versions_association_name,
          -> { order(model.timestamp_sort_order) },
          class_name: @model_class.version_class_name,
          as: :item
        )
      else
        @model_class.has_many(
          @model_class.versions_association_name,
          class_name: @model_class.version_class_name,
          as: :item,
          order: @model_class.paper_trail_version_class.timestamp_sort_order
        )
      end

      # Reset the transaction id when the transaction is closed.
      setup_transaction_callbacks
    end

    private

    def active_record_gem_version
      Gem::Version.new(ActiveRecord::VERSION::STRING)
    end

    def cannot_record_after_destroy?
      active_record_gem_version >= Gem::Version.new("5") &&
        ::ActiveRecord::Base.belongs_to_required_by_default
    end

    def setup_transaction_callbacks
      @model_class.after_commit :reset_transaction_id
      @model_class.after_rollback :reset_transaction_id
      @model_class.after_rollback { paper_trail.clear_rolled_back_versions }
    end
  end
end
