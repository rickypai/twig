require 'optparse'

class Twig
  module Cli

    def help_intro
      version_string = "Twig v#{Twig::VERSION}"

      intro = help_paragraph(%{
        Twig is your personal Git branch assistant. It shows you your most
        recent branches, and tracks issue tracker ids, tasks, and other metadata
        for your Git branches.
      })

      intro = <<-BANNER.gsub(/^[ ]+/, '')

        #{version_string}
        #{'-' * version_string.size}

        #{intro}

        http://rondevera.github.io/twig/
      BANNER

      intro + ' ' # Force extra blank line
    end

    def help_separator(option_parser, text, options={})
      options[:trailing] ||= "\n\n"
      option_parser.separator "\n#{text}#{options[:trailing]}"
    end

    def help_description(text, options={})
      width = options[:width] || 40
      words = text.gsub(/\n?\s+/, ' ').strip.split(' ')
      lines = []

      # Split words into lines
      while words.any?
        current_word = words.shift
        current_word_size = unformat_string(current_word).size
        last_line_size = lines.last && unformat_string(lines.last).size

        if last_line_size && (last_line_size + current_word_size + 1 <= width)
          lines.last << ' ' << current_word
        elsif current_word_size >= width
          lines << current_word[0...width]
          words.unshift(current_word[width..-1])
        else
          lines << current_word
        end
      end

      lines << ' ' if options[:add_separator]
      lines
    end

    def help_description_for_custom_property(option_parser, desc_lines)
      indent = '      '
      left_column_width = 29

      help_desc = desc_lines.inject('') do |desc, (left_column, right_column)|
        desc + indent +
        sprintf("%-#{left_column_width}s", left_column) + right_column + "\n"
      end

      help_separator(option_parser, help_desc, :trailing => "\n")
    end

    def help_paragraph(text)
      help_description(text, :width => 80).join("\n")
    end

    def help_line_for_custom_property?(line)
      is_custom_property_except = (
        line.include?('--except-') &&
        !line.include?('--except-branch') &&
        !line.include?('--except-PROPERTY')
      )
      is_custom_property_only = (
        line.include?('--only-') &&
        !line.include?('--only-branch') &&
        !line.include?('--only-PROPERTY')
      )
      is_custom_property_width = (
        line =~ /--.*-width/ &&
        !line.include?('--PROPERTY-width')
      )

      is_custom_property_except ||
      is_custom_property_only ||
      is_custom_property_width
    end

    def read_cli_options!(args)
      custom_properties = Twig::Branch.all_properties

      option_parser = OptionParser.new do |opts|
        opts.banner         = help_intro
        opts.summary_indent = ' ' * 2
        opts.summary_width  = 32



        help_separator(opts, 'Common options:')

        desc = 'Use a specific branch.'
        opts.on(
          '-b BRANCH', '--branch BRANCH', *help_description(desc)
        ) do |branch|
          set_option(:branch, branch)
        end

        desc = 'Unset a branch property.'
        opts.on('--unset PROPERTY', *help_description(desc)) do |property_name|
          set_option(:unset_property, property_name)
        end

        desc = 'Show this help content.'
        opts.on('--help', *help_description(desc)) do
          summary_lines = opts.to_s.split("\n")

          # Filter out custom property lines
          prev_line = nil
          summary_lines.each do |line|
            # Squash successive blank lines
            next if line == "\n" && prev_line == "\n"

            unless help_line_for_custom_property?(line)
              puts line
              prev_line = line
            end
          end

          exit
        end

        desc = 'Show Twig version.'
        opts.on('--version', *help_description(desc)) do
          puts Twig::VERSION; exit
        end



        help_separator(opts, 'Filtering branches:')

        desc = 'Only list branches below a given age.'
        opts.on(
          '--max-days-old AGE', *help_description(desc, :add_separator => true)
        ) do |age|
          set_option(:max_days_old, age)
        end

        desc = 'Only list branches whose name matches a given pattern.'
        opts.on(
          '--only-branch PATTERN',
          *help_description(desc, :add_separator => true)
        ) do |pattern|
          set_option(:property_only, :branch => pattern)
        end

        desc = 'Do not list branches whose name matches a given pattern.'
        opts.on('--except-branch PATTERN', *help_description(desc)) do |pattern|
          set_option(:property_except, :branch => pattern)
        end

        custom_properties.each do |property_name|
          opts.on("--only-#{property_name} PATTERN") do |pattern|
            set_option(:property_only, property_name.to_sym => pattern)
          end

          opts.on("--except-#{property_name} PATTERN") do |pattern|
            set_option(:property_except, property_name.to_sym => pattern)
          end
        end
        help_description_for_custom_property(opts, [
          ['--only-PROPERTY PATTERN',   'Only list branches with a given property'],
          ['',                          'that matches a given pattern.'],
        ])
        help_description_for_custom_property(opts, [
          ['--except-PROPERTY PATTERN', 'Do not list branches with a given property'],
          ['',                          'that matches a given pattern.']
        ])

        desc =
          'Lists all branches regardless of other filtering options. ' +
          'Useful for overriding options in ' +
          File.basename(Twig::Options::CONFIG_FILE) + '.'
        opts.on('--all', *help_description(desc)) do |pattern|
          unset_option(:max_days_old)
          unset_option(:property_except)
          unset_option(:property_only)
        end



        help_separator(opts, 'Listing branches:')

        custom_properties.each do |property_name|
          opts.on("--#{property_name}-width NUMBER") do |width|
            set_option(:property_width, property_name.to_sym => width)
          end
        end
        help_description_for_custom_property(opts, [
          ['--PROPERTY-width NUMBER', 'Set column width for a given property.']
        ])

        colors = Twig::Display::COLORS.keys.map do |value|
          format_string(value, :color => value)
        end.join(', ')
        weights = Twig::Display::WEIGHTS.keys.map do |value|
          format_string(value, :weight => value)
        end.join(' and ')
        default_color = format_string(
          Twig::DEFAULT_HEADER_COLOR.to_s,
          :color => Twig::DEFAULT_HEADER_COLOR
        )
        desc = <<-DESC
          STYLE is a color, weight, or a space-separated pair of one of each.
          Valid colors are #{colors}. Valid weights are #{weights}.
          The default is "#{default_color}".
        DESC
        opts.on('--header-style "STYLE"', *help_description(desc)) do |style|
          set_option(:header_style, style)
        end



        help_separator(opts, help_paragraph(%{
          You can put your most frequently used options for filtering and
          listing branches into #{Twig::Options::CONFIG_FILE}. For example:
        }), :trailing => '')

        help_separator(opts, [
          '      except-branch: staging',
          '      header-style:  green bold',
          '      max-days-old:  30'
        ].join("\n"), :trailing => '')

        help_separator(opts, help_paragraph(%{
          To enable tab completion for Twig, run `twig init-completion` and
          follow the instructions.
        }))
      end

      option_parser.parse!(args)
    rescue OptionParser::InvalidOption, OptionParser::MissingArgument => exception
      abort_for_option_exception(exception)
    end

    def abort_for_option_exception(exception)
      puts exception.message
      puts 'For a list of options, run `twig --help`.'
      exit
    end

    def read_cli_args!(args)
      if args.any?
        # Run subcommand binary, if any, and exit here
        possible_subcommand_name = args[0]
        command_path = Twig.run("which twig-#{possible_subcommand_name} 2>/dev/null")
        unless command_path.empty?
          command = ([command_path] + args[1..-1]).join(' ')
          exec(command)
        end
      end

      read_cli_options!(args)
      branch_name = options[:branch] || current_branch_name
      property_to_unset = options.delete(:unset_property)

      # Handle remaining arguments, if any
      if args.any?
        property_name, property_value = args[0], args[1]

        read_cli_options!(args)

        # Get/set branch property
        if property_value
          # `$ twig <key> <value>`
          set_branch_property_for_cli(branch_name, property_name, property_value)
        else
          # `$ twig <key>`
          get_branch_property_for_cli(branch_name, property_name)
        end
      elsif property_to_unset
        # `$ twig --unset <key>`
        unset_branch_property_for_cli(branch_name, property_to_unset)
      else
        # `$ twig`
        puts list_branches
      end
    end

    def get_branch_property_for_cli(branch_name, property_name)
      begin
        value = get_branch_property(branch_name, property_name)
        if value
          puts value
        else
          raise Twig::Branch::MissingPropertyError,
            %{The branch "#{branch_name}" does not have the property "#{property_name}".}
        end
      rescue ArgumentError, Twig::Branch::MissingPropertyError => exception
        abort exception.message
      end
    end

    def set_branch_property_for_cli(branch_name, property_name, property_value)
      begin
        puts set_branch_property(branch_name, property_name, property_value)
      rescue ArgumentError, RuntimeError => exception
        abort exception.message
      end
    end

    def unset_branch_property_for_cli(branch_name, property_name)
      begin
        puts unset_branch_property(branch_name, property_name)
      rescue ArgumentError, Twig::Branch::MissingPropertyError => exception
        abort exception.message
      end
    end

  end
end
