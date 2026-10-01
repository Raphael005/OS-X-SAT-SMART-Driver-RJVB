all: build pkg dmg

CONFIGURATION=Debug
SDK=macosx10.6
TITLE=SATSMARTDriver
ifneq ($(CONFIGURATION),Release) 
  VERSIONPOSTFIX := $(VERSIONPOSTFIX)-$(CONFIGURATION)
endif
ifneq ($(SDK),macosx10.6)
  VERSIONPOSTFIX := $(VERSIONPOSTFIX)-$(SDK)
endif
KEXTDIR=/Library/Extensions

# Optional signing; empty values give an unsigned (ad hoc) build.
#   SIGN_APP        "Developer ID Application: Name (TEAMID)" for kext, plugin, tools
#   SIGN_INSTALLER  "Developer ID Installer: Name (TEAMID)" for the package
# `make notarize` uses the Apple account signed into Xcode (see notarize-pkg.sh).
# A kext only loads if SIGN_APP's certificate also carries Apple's kext
# signing extension, which Apple grants on request.
SIGN_APP=
SIGN_INSTALLER=

build:
	rm -rf SATSMARTDriver/build
	(cd SATSMARTDriver; xcodebuild -configuration $(CONFIGURATION) -project SATSMARTDriver.xcodeproj)

version:
	$(eval VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' SATSMARTDriver/build/$(CONFIGURATION)/SATSMARTDriver.kext/Contents/Info.plist))
	echo VERSION $(VERSION)
	$(eval PKG := $(TITLE)-$(VERSION)-$(CONFIGURATION).pkg)
	echo PKG $(PKG)

#pkgbuild --analyze   --root Root   SATSMARTDriver.plist
#productbuild --synthesize     --package SATSMARTDriver.pkg    Distribution.xml

pkg: version
	rm -rf Root $(PKG)
	mkdir Root
	(cd SATSMARTDriver; xcodebuild -configuration $(CONFIGURATION) -project SATSMARTDriver.xcodeproj install DSTROOT=../Root)
	rm -f Root/usr/local/bin/smart_sample
	rm -f Root/usr/local/bin/set_properties
ifneq ($(SIGN_APP),)
	codesign --force --timestamp --options runtime --sign "$(SIGN_APP)" Root/usr/local/bin/*
	codesign --force --timestamp --options runtime --sign "$(SIGN_APP)" Root/Library/Extensions/SATSMARTLib.plugin
	codesign --force --timestamp --options runtime --sign "$(SIGN_APP)" Root/Library/Extensions/SATSMARTDriver.kext
endif
	pkgbuild --root Root  --component-plist SATSMARTDriver.plist --scripts PackageScripts --identifier fi.dungeon.SATSMARTDriver SATSMARTDriver.pkg
	productbuild --distribution ./Distribution.xml --resources Resources --package-path . $(if $(SIGN_INSTALLER),--sign "$(SIGN_INSTALLER)" --timestamp) $(PKG)
	#/Developer/Applications/Utilities/PackageMaker.app/Contents/MacOS/PackageMaker --doc SATSMARTDriver.pmdoc --out $(PKG)

notarize: version
	test -n "$(SIGN_APP)" || { echo "set SIGN_APP"; exit 1; }
	./notarize-pkg.sh $(PKG) "$(SIGN_APP)" Root/usr/local/bin/smart_status

dmg: version
	echo VERSION $(VERSION)$(VERSIONPOSTFIX)
	./mkdmg $(PKG) 0 $(TITLE) $(VERSION)$(VERSIONPOSTFIX)

unmount:
	ioreg -r -c IOSCSIPeripheralDeviceType00 -l | grep "BSD Name" | cut -d'"' -f4 | while read a; do diskutil unmountDisk "$$a" || exit 1; done

unload: unmount
	-sudo kmutil unload -b fi.dungeon.driver.SATSMARTDriver
	-sudo kmutil unload -b org.dungeon.driver.SATSMARTDriver

# Since macOS 11 third-party kexts load only from /Library/Extensions, so
# install and realinstall are the same; the first load needs user approval
# in System Settings > Privacy & Security and a restart.
install realinstall: unload
	sudo rm -rf $(KEXTDIR)/SATSMARTDriver.kext $(KEXTDIR)/SATSMARTLib.plugin
	sudo cp -R SATSMARTDriver/build/$(CONFIGURATION)/SATSMARTDriver.kext $(KEXTDIR)
	sudo cp -R SATSMARTDriver/build/$(CONFIGURATION)/SATSMARTLib.plugin $(KEXTDIR)
	sudo chown -R root:wheel $(KEXTDIR)/SATSMARTDriver.kext $(KEXTDIR)/SATSMARTLib.plugin
	sync
	sudo kmutil load -p $(KEXTDIR)/SATSMARTDriver.kext

uninstall: unload
	sudo rm -rf $(KEXTDIR)/SATSMARTDriver.kext
	sudo rm -rf $(KEXTDIR)/SATSMARTLib.plugin

clean:
	rm -rf SATSMARTDriver/build
	rm -rf Root
	rm -f SATSMARTDriver.pkg SATSMARTDriver-*-Release.pkg SATSMARTDriver-*-Debug.pkg

bump-version:
	cd SATSMARTDriver; xcrun agvtool new-version -all 0.11
