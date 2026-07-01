require 'software_version/version'

# Root namespace of the gem.
module SoftwareVersion
  # Version comparing like RPM (rpmvercmp, as used by rpm and dnf/yum).
  #
  # It differs from the generic Version on a few points:
  # - every non-alphanumeric character other than '~' and '^' is a mute
  #   separator, so `module+el8+2468` aligns with `module+el8.1.0+3366` the way
  #   dnf compares them, while the generic tokenizer keeps '+' as an ordered
  #   token and misaligns them;
  # - the string is first split into `[epoch:]version[-release]` on the last
  #   dash, and each part is compared fully before the next one;
  # - words carry no semantic (no pre-version like alpha/rc, no dropped
  #   rev/update) and are compared as raw case-sensitive strings;
  # - the number of segments matters: 1.0 > 1, unlike the generic 1.0 = 1.
  class Rpm < Version
    def <=>(other)
      other = SoftwareVersion.Rpm(other)
      cmp = epoch <=> other.epoch
      cmp = compare_tokens(version_tokens, other.version_tokens) if cmp.zero?
      cmp = compare_tokens(release_tokens, other.release_tokens) if cmp.zero?
      cmp
    end

    def epoch
      evr[0]
    end

    protected

    # Expose the version and release tokens, mostly for #version_parts. The
    # EOV of the version part keeps the first number sequence from leaking
    # into the release.
    def tokens
      @tokens ||= version_tokens + release_tokens
    end

    def version_tokens
      @version_tokens ||= parse(evr[1])
    end

    def release_tokens
      @release_tokens ||= parse(evr[2])
    end

    private

    # Split the raw string into [epoch, version, release] like rpm does: the
    # epoch is the leading digits before a ':' and defaults to 0, the release
    # is everything after the last '-' and defaults to "".
    def evr
      @evr ||= begin
        rest = @v.to_s
        epoch = 0
        if (match = rest.match(/\A(\d+):(.*)\z/m))
          epoch = match[1].to_i
          rest = match[2]
        end
        dash = rest.rindex('-')
        dash ? [epoch, rest[0...dash], rest[(dash + 1)..]] : [epoch, rest, '']
      end
    end

    # rpm keeps only numbers, words, '~' and '^'; every other character is a
    # separator without semantic value. Words are left raw: rpmvercmp has no
    # special words and compares them as case-sensitive ASCII strings.
    #
    # A trailing '^' keeps the generic "highest version possible" meaning
    # instead of rpmvercmp's ("1.0^" > "1.0" but < "1.0.1"), so that ranges
    # like `>= 1.0, <= 1.0^` keep matching every 1.0 subversion. Real rpm
    # versions never end with '^', so this exception costs no fidelity.
    def parse(version_string)
      semantic_tokens = []
      literal_tokens = lex(version_string)
      literal_tokens << nil # Sentinel for each_cons.
      literal_tokens.each_cons(2) do |current, ahead|
        case current[0]
        when Token::DOT, Token::UNDERSCORE, Token::COLON,
             Token::DASH, Token::PLUS
          # Mute separators.
        when Token::CARET
          semantic_tokens << (ahead[0] == Token::EOV ? [Token::MAX, current[1]] : current)
        else
          semantic_tokens << current
        end
      end
      semantic_tokens
    end
  end

  # Convert the argument to an Rpm version. An existing Rpm is reused as-is;
  # any other Version or String is (re)wrapped so it compares with rpm/dnf
  # semantics.
  def Rpm(version)
    return version if version.is_a?(Rpm)

    Rpm.new(version.is_a?(Version) ? version.v : version.to_s)
  end
  module_function :Rpm
end
