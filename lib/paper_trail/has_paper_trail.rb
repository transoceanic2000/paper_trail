require "active_support/core_ext/object" # provides the `try` method
require "paper_trail/attributes_serialization"
require "paper_trail/model_config"
require "paper_trail/record_trail"

module PaperTrail
  # Extensions to `ActiveRecord::Base`.  See `frameworks/active_record.rb`.
  module Model
    def self.included(base)
      base.send :extend, ClassMethods
    end

    # :nodoc:
    module ClassMethods
      # Declare this in your model to track every create, update, and destroy.
      # Each version of the model is available in the `versions` association.
      #
      # Options:
      #
      # - :on - The events to track (optional; defaults to all of them). Set
      #   to an array of `:create`, `:update`, `:destroy` as desired.
      # - :class_name - The name of a custom Version class.  This class should
      #   inherit from `PaperTrail::Version`.
      # - :ignore - An array of attributes for which a new `Version` will not be
      #   created if only they change. It can also aceept a Hash as an
      #   argument where the key is the attribute to ignore (a `String` or
      #   `Symbol`), which will only be ignored if the value is a `Proc` which
      #   returns truthily.
      # - :if, :unless - Procs that allow to specify conditions when to save
      #   versions for an object.
      # - :only - Inverse of `ignore`. A new `Version` will be created only
      #   for these attributes if supplied it can also aceept a Hash as an
      #   argument where the key is the attribute to track (a `String` or
      #   `Symbol`), which will only be counted if the value is a `Proc` which
      #   returns truthily.
      # - :skip - Fields to ignore completely.  As with `ignore`, updates to
      #   these fields will not create a new `Version`.  In addition, these
      #   fields will not be included in the serialized versions of the object
      #   whenever a new `Version` is created.
      # - :meta - A hash of extra data to store. You must add a column to the
      #   `versions` table for each key. Values are objects or procs (which
      #   are called with `self`, i.e. the model with the paper trail).  See
      #   `PaperTrail::Controller.info_for_paper_trail` for how to store data
      #   from the controller.
      # - :versions - The name to use for the versions association.  Default
      #   is `:versions`.
      # - :version - The name to use for the method which returns the version
      #   the instance was reified from. Default is `:version`.
      # - :save_changes - Whether or not to save changes to the object_changes
      #   column if it exists. Default is true
      #
      def has_paper_trail(options = {})
        options[:on] ||= [:create, :update, :destroy]

        # Wrap the :on option in an array if necessary. This allows a single
        # symbol to be passed in.
        options[:on] = Array(options[:on])

        paper_trail.setup(options)
        setup_callbacks_from_options options[:on]
      end

      def paper_trail
        ::PaperTrail::ModelConfig.new(self)
      end

      def paper_trail_deprecate(new_method, old_method = nil)
        old = old_method.nil? ? new_method : old_method
        msg = format("Use paper_trail.%s instead of %s", new_method, old)
        ::ActiveSupport::Deprecation.warn(msg, caller(2))
      end

      def setup_model_for_paper_trail(*args)
        paper_trail_deprecate "setup", "setup_model_for_paper_trail"
        paper_trail.setup(*args)
      end

      def setup_callbacks_from_options(options_on = [])
        options_on.each do |event|
          paper_trail.public_send("on_#{event}")
        end
      end

      def paper_trail_on_destroy(*args)
        paper_trail_deprecate "on_destroy", "paper_trail_on_destroy"
        paper_trail_on_destroy(*args)
      end

      def paper_trail_on_update
        paper_trail_deprecate "on_update", "paper_trail_on_update"
        paper_trail.on_update
      end

      def paper_trail_on_create
        paper_trail_deprecate "on_create", "paper_trail_on_create"
        paper_trail.on_create
      end

      def paper_trail_off!
        paper_trail_deprecate "disable", "paper_trail_off!"
        paper_trail.disable
      end

      def paper_trail_on!
        paper_trail_deprecate "enable", "paper_trail_on!"
        paper_trail.enable
      end

      def paper_trail_enabled_for_model?
        paper_trail_deprecate "enabled?", "paper_trail_enabled_for_model?"
        paper_trail.enabled?
      end

      def paper_trail_version_class
        @paper_trail_version_class ||= version_class_name.constantize
      end
    end

    # Wrap the following methods in a module so we can include them only in the
    # ActiveRecord models that declare `has_paper_trail`.
    module InstanceMethods
      def paper_trail
        ::PaperTrail::RecordTrail.new(self)
      end

      def live?
        self.class.paper_trail_deprecate "live?"
        paper_trail.live?
      end

      # Returns who put the object into its current state.
      def paper_trail_originator
        self.class.paper_trail_deprecate "originator", "paper_trail_originator"
        paper_trail.originator
      end

      def originator
        self.class.paper_trail_deprecate "originator"
        paper_trail.originator
      end

      def clear_rolled_back_versions
        self.class.paper_trail_deprecate "clear_rolled_back_versions"
        paper_trail.clear_rolled_back_versions
      end

      def source_version
        self.class.paper_trail_deprecate "source_version"
        paper_trail.source_version
      end

      def version_at(*args)
        self.class.paper_trail_deprecate "version_at"
        paper_trail.version_at(*args)
      end

      # Returns the objects (not Versions) as they were between the given times.
      # TODO: Either add support for the third argument, `_reify_options`, or
      # add a deprecation warning if someone tries to use it.
      def versions_between(start_time, end_time, _reify_options = {})
        versions = send(self.class.versions_association_name).between(start_time, end_time)
        versions.collect { |version|
          paper_trail.version_at(version.send(PaperTrail.timestamp_field))
        }
      end

      # Returns the object (not a Version) as it was most recently.
      def previous_version
        self.class.paper_trail_deprecate "previous_version"
        paper_trail.previous_version
      end

      # Returns the object (not a Version) as it became next.
      # NOTE: if self (the item) was not reified from a version, i.e. it is the
      #  "live" item, we return nil.  Perhaps we should return self instead?
      def next_version
        subsequent_version = paper_trail.source_version.next
        subsequent_version ? subsequent_version.reify : self.class.find(id)
      rescue
        nil
      end

      def paper_trail_enabled_for_model?
        self.class.paper_trail.enabled?
      end

      # Executes the given method or block without creating a new version.
      def without_versioning(method = nil)
        paper_trail_was_enabled = paper_trail_enabled_for_model?
        self.class.paper_trail.disable
        method ? method.to_proc.call(self) : yield(self)
      ensure
        self.class.paper_trail.enable if paper_trail_was_enabled
      end

      # Utility method for reifying. Anything executed inside the block will
      # appear like a new record.
      # rubocop: disable Style/Alias
      def appear_as_new_record
        instance_eval {
          alias :old_new_record? :new_record?
          alias :new_record? :present?
        }
        yield
        instance_eval { alias :new_record? :old_new_record? }
      end
      # rubocop: enable Style/Alias

      # Temporarily overwrites the value of whodunnit and then executes the
      # provided block.
      def whodunnit(value)
        raise ArgumentError, "expected to receive a block" unless block_given?
        current_whodunnit = PaperTrail.whodunnit
        PaperTrail.whodunnit = value
        yield self
      ensure
        PaperTrail.whodunnit = current_whodunnit
      end

      # Mimics the `touch` method from `ActiveRecord::Persistence`, but also
      # creates a version. A version is created regardless of options such as
      # `:on`, `:if`, or `:unless`.
      #
      # TODO: look into leveraging the `after_touch` callback from
      # `ActiveRecord` to allow the regular `touch` method to generate a version
      # as normal. May make sense to switch the `record_update` method to
      # leverage an `after_update` callback anyways (likely for v4.0.0)
      def touch_with_version(name = nil)
        raise ActiveRecordError, "can not touch on a new record object" unless persisted?

        attributes = timestamp_attributes_for_update_in_model
        attributes << name if name
        current_time = current_time_from_proper_timezone

        attributes.each { |column| write_attribute(column, current_time) }

        record_update(true) unless will_record_after_update?
        save!(validate: false)
      end

      private

      # Returns true if `save` will cause `record_update`
      # to be called via the `after_update` callback.
      def will_record_after_update?
        on = paper_trail_options[:on]
        on.nil? || on.include?(:update)
      end

      def record_create
        if paper_trail_switched_on?
          data = {
            event: paper_trail_event || "create",
            whodunnit: PaperTrail.whodunnit
          }
          if respond_to?(:updated_at)
            data[PaperTrail.timestamp_field] = updated_at
          end
          if pt_record_object_changes? && changed_notably?
            data[:object_changes] = pt_recordable_object_changes
          end
          if self.class.paper_trail_version_class.column_names.include?("transaction_id")
            data[:transaction_id] = PaperTrail.transaction_id
          end
          version = send(self.class.versions_association_name).create! merge_metadata(data)
          update_transaction_id(version)
          save_associations(version)
        end
      end

      def record_update(force = nil)
        if paper_trail_switched_on? && (force || changed_notably?)
          data = {
            event: paper_trail_event || "update",
            object: pt_recordable_object,
            whodunnit: PaperTrail.whodunnit
          }
          if respond_to?(:updated_at)
            data[PaperTrail.timestamp_field] = updated_at
          end
          if pt_record_object_changes?
            data[:object_changes] = pt_recordable_object_changes
          end
          if self.class.paper_trail_version_class.column_names.include?("transaction_id")
            data[:transaction_id] = PaperTrail.transaction_id
          end
          version = send(self.class.versions_association_name).create merge_metadata(data)
          update_transaction_id(version)
          save_associations(version)
        end
      end

      # Returns a boolean indicating whether to store serialized version diffs
      # in the `object_changes` column of the version record.
      # @api private
      def pt_record_object_changes?
        paper_trail_options[:save_changes] &&
          self.class.paper_trail_version_class.column_names.include?("object_changes")
      end

      # Returns an object which can be assigned to the `object` attribute of a
      # nascent version record. If the `object` column is a postgres `json`
      # column, then a hash can be used in the assignment, otherwise the column
      # is a `text` column, and we must perform the serialization here, using
      # `PaperTrail.serializer`.
      # @api private
      def pt_recordable_object
        if self.class.paper_trail_version_class.object_col_is_json?
          object_attrs_for_paper_trail
        else
          PaperTrail.serializer.dump(object_attrs_for_paper_trail)
        end
      end

      # Returns an object which can be assigned to the `object_changes`
      # attribute of a nascent version record. If the `object_changes` column is
      # a postgres `json` column, then a hash can be used in the assignment,
      # otherwise the column is a `text` column, and we must perform the
      # serialization here, using `PaperTrail.serializer`.
      # @api private
      def pt_recordable_object_changes
        if self.class.paper_trail_version_class.object_changes_col_is_json?
          changes_for_paper_trail
        else
          PaperTrail.serializer.dump(changes_for_paper_trail)
        end
      end

      def changes_for_paper_trail
        notable_changes = changes.delete_if { |k, _v| !notably_changed.include?(k) }
        self.class.serialize_attribute_changes_for_paper_trail!(notable_changes)
        notable_changes.to_hash
      end

      # Invoked via`after_update` callback for when a previous version is
      # reified and then saved.
      def clear_version_instance!
        send("#{self.class.version_association_name}=", nil)
      end

      # Invoked via callback when a user attempts to persist a reified
      # `Version`.
      def reset_timestamp_attrs_for_update_if_needed!
        return if paper_trail.live?
        timestamp_attributes_for_update_in_model.each do |column|
          # ActiveRecord 4.2 deprecated `reset_column!` in favor of
          # `restore_column!`.
          if respond_to?("restore_#{column}!")
            send("restore_#{column}!")
          else
            send("reset_#{column}!")
          end
        end
      end

      def record_destroy
        if paper_trail_switched_on? && !new_record?
          data = {
            item_id: id,
            item_type: self.class.base_class.name,
            event: paper_trail_event || "destroy",
            object: pt_recordable_object,
            whodunnit: PaperTrail.whodunnit
          }
          if self.class.paper_trail_version_class.column_names.include?("transaction_id")
            data[:transaction_id] = PaperTrail.transaction_id
          end
          version = self.class.paper_trail_version_class.create(merge_metadata(data))
          send("#{self.class.version_association_name}=", version)
          send(self.class.versions_association_name).send :load_target
          update_transaction_id(version)
          save_associations(version)
        end
      end

      # Saves associations if the join table for `VersionAssociation` exists.
      def save_associations(version)
        return unless PaperTrail.config.track_associations?
        self.class.reflect_on_all_associations(:belongs_to).each do |assoc|
          assoc_version_args = {
            version_id: version.id,
            foreign_key_name: assoc.foreign_key
          }

          if assoc.options[:polymorphic]
            associated_record = send(assoc.name) if send(assoc.foreign_type)
            if associated_record && associated_record.class.paper_trail.enabled?
              assoc_version_args[:foreign_key_id] = associated_record.id
            end
          elsif assoc.klass.paper_trail.enabled?
            assoc_version_args[:foreign_key_id] = send(assoc.foreign_key)
          end

          if assoc_version_args.key?(:foreign_key_id)
            PaperTrail::VersionAssociation.create(assoc_version_args)
          end
        end
      end

      def reset_transaction_id
        PaperTrail.transaction_id = nil
      end

      def merge_metadata(data)
        # First we merge the model-level metadata in `meta`.
        paper_trail_options[:meta].each do |k, v|
          data[k] =
            if v.respond_to?(:call)
              v.call(self)
            elsif v.is_a?(Symbol) && respond_to?(v, true)
              # If it is an attribute that is changing in an existing object,
              # be sure to grab the current version.
              if has_attribute?(v) && send("#{v}_changed?".to_sym) && data[:event] != "create"
                send("#{v}_was".to_sym)
              else
                send(v)
              end
            else
              v
            end
        end

        # Second we merge any extra data from the controller (if available).
        data.merge(PaperTrail.controller_info || {})
      end

      def attributes_before_change
        changed = changed_attributes.select { |k, _v| self.class.column_names.include?(k) }
        attributes.merge(changed)
      end

      # Returns hash of attributes (with appropriate attributes serialized),
      # ommitting attributes to be skipped.
      def object_attrs_for_paper_trail
        attrs = attributes_before_change.except(*paper_trail_options[:skip])
        self.class.serialize_attributes_for_paper_trail!(attrs)
        attrs
      end

      # Determines whether it is appropriate to generate a new version
      # instance. A timestamp-only update (e.g. only `updated_at` changed) is
      # considered notable unless an ignored attribute was also changed.
      def changed_notably?
        if ignored_attr_has_changed?
          timestamps = timestamp_attributes_for_update_in_model.map(&:to_s)
          (notably_changed - timestamps).any?
        else
          notably_changed.any?
        end
      end

      # An attributed is "ignored" if it is listed in the `:ignore` option
      # and/or the `:skip` option.  Returns true if an ignored attribute has
      # changed.
      def ignored_attr_has_changed?
        ignored = paper_trail_options[:ignore] + paper_trail_options[:skip]
        ignored.any? && (changed & ignored).any?
      end

      def notably_changed
        only = paper_trail_options[:only].dup
        # Remove Hash arguments and then evaluate whether the attributes (the
        # keys of the hash) should also get pushed into the collection.
        only.delete_if do |obj|
          obj.is_a?(Hash) &&
            obj.each { |attr, condition|
              only << attr if condition.respond_to?(:call) && condition.call(self)
            }
        end
        only.empty? ? changed_and_not_ignored : (changed_and_not_ignored & only)
      end

      def changed_and_not_ignored
        ignore = paper_trail_options[:ignore].dup
        # Remove Hash arguments and then evaluate whether the attributes (the
        # keys of the hash) should also get pushed into the collection.
        ignore.delete_if do |obj|
          obj.is_a?(Hash) &&
            obj.each { |attr, condition|
              ignore << attr if condition.respond_to?(:call) && condition.call(self)
            }
        end
        skip = paper_trail_options[:skip]
        changed - ignore - skip
      end

      def paper_trail_switched_on?
        PaperTrail.enabled? &&
          PaperTrail.enabled_for_controller? &&
          paper_trail_enabled_for_model?
      end

      def save_version?
        if_condition = paper_trail_options[:if]
        unless_condition = paper_trail_options[:unless]
        (if_condition.blank? || if_condition.call(self)) && !unless_condition.try(:call, self)
      end

      # @api private
      def update_transaction_id(version)
        return unless self.class.paper_trail_version_class.column_names.include?("transaction_id")
        if PaperTrail.transaction? && PaperTrail.transaction_id.nil?
          PaperTrail.transaction_id = version.id
          version.transaction_id = version.id
          version.save
        end
      end
    end
  end
end
