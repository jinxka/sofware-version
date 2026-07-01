require 'spec_helper'

module SoftwareVersion
  describe Version do
    it 'check version 4' do
      a = Version.new('4.1.2-29.el6')
      b = Version.new('4.1.2-15.el6_5')
      expect(a > b).to be true
    end

    it 'check version 5' do
      a = Version.new('2014.1.98-65.1.el6')
      b = Version.new('2013.1.95-65.1.el6_5')
      expect(a > b).to be true
    end

    it 'check version 6' do
      a = Version.new('4.1.1-43.P1.el6.centos')
      b = Version.new('4.1.1-34.P1.el6')
      expect(a > b).to be true
    end

    it 'check version 7' do
      a = Version.new('2.6.32-504.el6')
      b = Version.new('2.6.32-504.12.2.el6')
      expect(a < b).to be true
    end

    it 'check version 8' do
      a = Version.new('5.3p1-104.el6')
      b = Version.new('5.3p1-94.el6')
      expect(a > b).to be true
    end

    it 'check version 9' do
      a = Version.new('7.19.7-37.el6_5.3')
      b = Version.new('7.19.7-37.el6_5')
      expect(a > b).to be true
    end

    it 'check version 15' do
      a = Version.new('3.14.3-23.3.el6_8')
      b = Version.new('3.14.3-23.el6_7')
      expect(a > b).to be_truthy
    end

    context 'with SoftwareVersion::Rpm (rpmvercmp semantics)' do
      def rpm(str)
        Rpm.new(str)
      end

      # Regression: modular dist-tags misaligned under the generic tokenizer
      # because '.' is dropped but '+' is kept. dnf/rpm consider the el8 build
      # (build id 2468) newer than the el8.1.0 build here, because after the
      # equal `el8` it compares 2468 vs 1.
      it 'orders modular dist-tags like dnf' do
        a = rpm('1.0.1-10.module+el8+2468+c564cec5')
        b = rpm('1.0.1-10.module+el8.1.0+3366+6dfb954c')
        expect(a > b).to be true
        expect(b < a).to be true # symmetric regardless of operand order
        # Installed package of the original report, with its arch suffix.
        expect(rpm('1.0.1-10.module+el8+2468+c564cec5.x86_64') > b).to be true
      end

      it 'stays symmetric when compared against a generic Version' do
        a = rpm('1.0.1-10.module+el8+2468+c564cec5')
        b = Version.new('1.0.1-10.module+el8.1.0+3366+6dfb954c')
        expect(b < a).to be true
        expect(a > b).to be true
      end

      it 'compares against a plain string operand with rpm semantics' do
        expect(rpm('1.0.1-10.module+el8+2468+c564cec5') >
               '1.0.1-10.module+el8.1.0+3366+6dfb954c').to be true
      end

      it 'treats ~ as a pre-release lower than the release' do
        expect(rpm('1.0-1~beta') < rpm('1.0-1')).to be true
        expect(rpm('1.0~rc1') < rpm('1.0~rc2')).to be true
      end

      # Exception to rpmvercmp so that ranges like `>= 1.0, <= 1.0^` keep
      # matching every subversion. Real rpm versions never end with '^'.
      it 'keeps the generic trailing-^ = highest version rule' do
        expect(rpm('1.0.^') > rpm('1.0.999999')).to be true
        expect(rpm('1.0.5-1') < rpm('1.0.^')).to be true
        expect(rpm('1.0-1^') > rpm('1.0-1.el8')).to be true # trailing ^ of a release
      end

      it 'treats every character but ASCII letters, digits, ~ and ^ as a separator' do
        expect(rpm('1.0%a') == rpm('1.0a')).to be true
        expect(rpm('1.0-1/2') == rpm('1.0-1.2')).to be true
        expect(rpm('1.0é') == rpm('1.0')).to be true
      end

      it 'counts each ~ and ^ on its own' do
        expect(rpm('1.0~~') < rpm('1.0~')).to be true
        expect(rpm('1.0~rc1') > rpm('1.0~~')).to be true
        expect(rpm('1.0^^1') < rpm('1.0^1')).to be true
      end

      # A non-trailing ^ marks a post-release snapshot: newer than the bare
      # version, older than any other continuation.
      it 'ranks ^ above the end of version and below any other segment' do
        expect(rpm('1.0^git1') > rpm('1.0')).to be true
        expect(rpm('1.0^git1') < rpm('1.0a')).to be true
        expect(rpm('1.0^git1') < rpm('1.0.1')).to be true
      end

      it 'ranks a missing release below any present one' do
        expect(rpm('1.0') < rpm('1.0-')).to be true
        expect(rpm('1.0') < rpm('1.0-~rc1')).to be true
        expect(rpm('1.0') == rpm('0:1.0')).to be true
      end

      it 'lets the epoch dominate the rest of the version' do
        expect(rpm('2:1.0-1') > rpm('1.0-9')).to be true
        # Higher epoch with a lower version: the epoch is compared first.
        expect(rpm('2:1-82.module+el8.10.0+23647+cfd78660') > rpm('1:1.2')).to be true
      end

      it 'keeps the hand-written el6 cases correct' do
        expect(rpm('4.1.2-29.el6') > rpm('4.1.2-15.el6_5')).to be true
        expect(rpm('2.6.32-504.el6') < rpm('2.6.32-504.12.2.el6')).to be true
        expect(rpm('7.19.7-37.el6_5.3') > rpm('7.19.7-37.el6_5')).to be true
      end

      # rpm_vercmp_sort.txt is rpm_version.txt sorted by the real rpmvercmp
      # (rpm.vercmp from rpm 4.19 in a Fedora container). Versions rpm finds
      # equal share a tab-separated line, so this asserts that Rpm reproduces
      # rpm's own ordering and equalities over the whole corpus.
      context 'rpmvercmp sort file test' do
        @version_lines = fixture('rpm_vercmp_sort.txt').split("\n").map { |line| line.split("\t") }
        @version_lines.each_cons(2) do |lower, higher|
          it "compare #{lower.join(' = ')} < #{higher.join(' = ')}" do
            expect(Rpm.new(lower.last) < Rpm.new(higher.first)).to be true
            higher.each_cons(2) { |a, b| expect(Rpm.new(a) == Rpm.new(b)).to be true }
          end
        end
      end
    end

    context 'Sort file test' do
      before(:all) do
        @version_array = fixture('rpm_version_sort.txt').split("\n")
      end

      @version_array = fixture('rpm_version_sort.txt').split("\n")
      @version_array.each_index do |k|
        it "compare #{@version_array[k]} <= #{@version_array[k + 1]}" do
          next if @version_array[k + 1].nil? || @version_array[k + 1] == ''

          a = Version.new(@version_array[k])
          b = Version.new(@version_array[k + 1])
          expect(a <= b).to be true
        end
      end
    end
  end
end
