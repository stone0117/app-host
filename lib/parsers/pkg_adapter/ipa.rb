module PkgAdapter

  class Ipa < BaseAdapter
    
    require 'zip'

    def parse
        Zip::File.open(@path) do |zip_file|
          # Handle entries one by one
          path = tmp_dir
          FileUtils.rm_rf path
          # zip_file.each do |entry|
          #   # Extract to file/directory/symlink
          #   p "Extracting #{entry.name}"
          #   entry.extract("#{path}/#{entry.name}")
          #   # content = entry.get_input_stream.read if entry.get_input_stream.respond_to? :read
          # end

          profile_contents = zip_file.glob('Payload/*.app/embedded.mobileprovision').first.get_input_stream.read
          @profile = ConfigParser.mobileprovision profile_contents

          plist = zip_file.glob('Payload/*.app/Info.plist').first.get_input_stream.read
          
          @plist = ConfigParser.plist plist

          entry = zip_file.glob('Payload/*.app/AppIcon[6,4]0x[6,4]0@[2,3]x.png').last
          if entry
            @app_icon = "#{path}/#{entry.name}"
            dirname = File.dirname(@app_icon)
            FileUtils.mkdir_p dirname

            entry.extract @app_icon
            
            #uncrush
            png = PNG.normalize(@app_icon)
            File.open("#{@app_icon}", 'wb') { |file| file.write(png) } if png
          else
            p "can find AppIcon"
          end
        end
    end

    def plat
      'ios'
    end

    def app_uniq_key
      :build
    end

    def app_name
      @plist["CFBundleDisplayName"] || @plist["CFBundleName"]
    end

    def app_version
      @plist["CFBundleShortVersionString"]
    end

    def app_build
      @plist["CFBundleVersion"]
    end

    def app_icon
      @app_icon
    end

    def app_size
      File.size(@path)
    end

    def app_bundle_id
      @plist["CFBundleIdentifier"]
    end

    def ext_info
      devices = @profile["ProvisionedDevices"];
      info = {
        "包类型" => devices ? "Ad-hoc" : "Release",
        "包信息" => [
          "包名: #{self.app_bundle_id}",
          "体积: #{app_size_mb}MB",
          "MD5: #{pkg_mb5}"
        ],
        "描述文件" => [
          "名称: #{@profile['Name']}",
          "TeamName: #{@profile['TeamName']}",
          "TeamID: #{@profile['TeamIdentifier'].join(',')}",
          "创建时间: #{@profile['CreationDate']}",
          "过期时间: #{@profile['ExpirationDate']}",
          "UUID: #{@profile['UUID']}",
        ],
        "Entitlements" => @profile['Entitlements'].map{|k,v| "#{k}: #{v}" },
      }
      if devices
        info["包含设备 (#{devices.count}台)"] = devices
      end
      info
    end

  end

  class ConfigParser
    def self.mobileprovision(stream)
      # security cms -D -i Reutte.app/embedded.mobileprovision
      profile = stream.slice(stream.index('<?'), stream.length)
      self.plist(Nokogiri.XML(profile).to_xml)
    end

    def self.plist(stream)
      if stream[0..5] == "bplist"
        Bplist.parse(stream).tree
      else
        Plist.parse_xml(stream)
      end
    end
  end
end