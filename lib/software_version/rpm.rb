require 'software_version/version'

# Root namespace of the gem.
module SoftwareVersion
  # Version comparing like RPM (rpmvercmp, as used by rpm and dnf/yum).
  #
  # It differs from the generic Version on a few points:
  # - only ASCII letters, digits, '~' and '^' matter, every other character is
  #   a mute separator, so `module+el8+2468` aligns with `module+el8.1.0+3366`
  #   the way dnf compares them, while the generic tokenizer keeps '+' as an
  #   ordered token and misaligns them;
  # - each '~' and '^' counts on its own: 1.0~~ < 1.0~;
  # - the string is first split into `[epoch:]version[-release]` on the last
  #   dash, and each part is compared fully before the next one. A missing
  #   release sorts below any present one: 1.0 < 1.0-~rc1;
  # - words carry no semantic (no pre-version like alpha/rc, no dropped
  #   rev/update) and are compared as raw case-sensitive strings;
  # - the number of segments matters: 1.0 > 1, unlike the generic 1.0 = 1.
  class Rpm < Version
    def <=>(other)
      other = SoftwareVersion.Rpm(other)
      cmp = epoch <=> other.epoch
      cmp = compare_tokens(version_tokens, other.version_tokens) if cmp.zero?
      cmp = compare_releases(other) if cmp.zero?
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
      @release_tokens ||= parse(evr[2].to_s)
    end

    def release
      evr[2]
    end

    private

    # Split the raw string into [epoch, version, release] like rpm does: the
    # epoch is the leading digits before a ':' and defaults to 0, the release
    # is everything after the last '-' and is nil without a dash.
    def evr
      @evr ||= begin
        rest = @v.to_s
        epoch = 0
        if (match = rest.match(/\A(\d+):(.*)\z/m))
          epoch = match[1].to_i
          rest = match[2]
        end
        dash = rest.rindex('-')
        dash ? [epoch, rest[0...dash], rest[(dash + 1)..]] : [epoch, rest, nil]
      end
    end

    # Releases are only compared when both sides have one. Otherwise the side
    # with a release is the newer, whatever the release holds: 1.0 < 1.0- and
    # 1.0 < 1.0-~rc1, like rpm.vercmp and dnf.
    def compare_releases(other)
      return compare_tokens(release_tokens, other.release_tokens) if release && other.release

      (release ? 1 : 0) <=> (other.release ? 1 : 0)
    end

    # rpmvercmp works on bytes and keeps only runs of ASCII digits, runs of
    # ASCII letters, and each '~' or '^' on its own; every other byte is a
    # separator without semantic value. Words are left raw: rpmvercmp has no
    # special words and compares them as case-sensitive ASCII strings.
    def lex(version_string)
      tokens = version_string.b.scan(/[0-9]+|[A-Za-z]+|[~^]/).map do |chunk|
        case chunk
        when '~' then [Token::TILDE, chunk]
        when '^' then [Token::CARET, chunk]
        when /\A[0-9]/ then [Token::NUMBER, chunk.to_i]
        else [Token::WORD, chunk]
        end
      end
      tokens << [Token::EOV, nil]
    end

    # A trailing '^' keeps the generic "highest version possible" meaning
    # instead of rpmvercmp's ("1.0^" > "1.0" but < "1.0.1"), so that ranges
    # like `>= 1.0, <= 1.0^` keep matching every 1.0 subversion. Real rpm
    # versions never end with '^', so this exception costs no fidelity.
    def parse(version_string)
      tokens = lex(version_string)
      tokens[-2] = [Token::MAX, tokens[-2][1]] if tokens[-2]&.first == Token::CARET
      tokens
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
