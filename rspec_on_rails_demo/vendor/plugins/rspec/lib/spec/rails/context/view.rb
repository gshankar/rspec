module Spec
  module Rails
    class ViewEvalContext < Spec::Rails::FunctionalEvalContext

      attr_reader :response

      def setup
        super
        # these go here so that flash and session work as they should.
        @controller.send :initialize_template_class, @response
        begin
          @controller.send :assign_shortcuts, @request, @response
        rescue => e
          unless e.message =~ /^Deprecating.*/
            raise e
          end
        end
        @controller.send :reset_session

        assigns[:session] = @controller.session
        @controller.class.send :public, :flash # make flash accessible to the spec
      end

      def set_base_view_path(options)
        ActionView::Base.base_view_path = base_view_path(options)
      end

      def base_view_path(options)
        "/#{derived_controller_name(options)}/"
      end

      def derived_controller_name(options)
        parts = subject_of_render(options).split('/').reject { |part| part.empty? }
        "#{parts[0..-2].join('/')}"
      end
      
      def subject_of_render(options)
        [:template, :partial, :file].each do |render_type|
          if options.has_key?(render_type)
            return options[render_type]
          end
        end
        raise Exception.new("Unhandled render type in view spec.")
      end

      def render(*options)
        options = Spec::Rails::OptsMerger.new(options).merge(:template)
        set_base_view_path(options)
        @controller.add_helper("application")
        @controller.add_helper(derived_controller_name(options))
        @controller.add_helper(options[:helper]) if options[:helper]
        if options[:helpers]
          options[:helpers].each { |helper| @controller.add_helper(helper) }
        end

        @action_name = action_name caller[0] if options.empty?
        assigns[:action_name] = @action_name

        @request.path_parameters = {
          :controller => @controller.controller_name,
          :action => @action_name,
        }

        defaults = { :layout => false }
        options = defaults.merge options

        @controller.instance_variable_set :@params, @request.parameters
        @controller.send :initialize_current_url
        @controller.class.instance_eval %{
          def controller_path
            "#{derived_controller_name(options)}"
          end
        }

        # Rails 1.0
        @controller.send :assign_names rescue nil
        @controller.send :fire_flash rescue nil

        # Rails 1.1
        @controller.send :forget_variables_added_to_assigns rescue nil

        # Do the render
        @controller.render options

        # Rails 1.1
        @controller.send :process_cleanup rescue nil
      end
    end

    class ViewSpecController < ActionController::Base
      attr_reader :template

      def add_helper_for(template_path)
        add_helper(template_path.split('/')[0])
      end

      def add_helper(name)
        begin
          helper_module = "#{name}_helper".camelize.constantize
        rescue
          return
        end
        (class << template; self; end).class_eval do
          include helper_module
        end
      end
    end

    class ViewContext < Spec::Rails::Context
      def execution_context specification=nil
        instance = execution_context_class.new(specification)
        instance.instance_eval { @controller_class_name = "Spec::Rails::ViewSpecController" }
        instance
      end
      def before_context_eval
        inherit Spec::Rails::ViewEvalContext
      end
    end
  end
end

