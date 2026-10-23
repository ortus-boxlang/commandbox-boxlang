/**
 * Open the BoxLang CLI
 * .
 * {code:bash}
 * boxlang cli
 * {code}
 * .
 * This command has no arguments.  Any args passed positionally will be sent along to the BoxLang binary
 * .
 * {code:bash}
 * boxlang cli myFile.bxs
 * {code}
 * .
 **/
component {

	// DI
	property name="javaService"     inject="JavaService";
	property name="endpointService" inject="EndpointService";
	property name="semanticVersion" inject="provider:semanticVersion@semver";
	property name="packageService"  inject="PackageService";
	property name="commandService"  inject="CommandService";
	property name="moduleSettings"  inject="box:moduleSettings:commandbox-boxlang";

	function run(){
		var verbose         = moduleSettings.CLIVerbose ?: false;
		var javaInstallPath = locateJavaBinary( verbose );
		if ( verbose ) print.line( "Using Java from: " & javaInstallPath );

		var cmd = """#javaInstallPath#""";

		setBoxlangHomeToServer();
		var localBoxlangJarPath = getJarPath();

		cmd &= " -cp ""#localBoxlangJarPath#"" ortus.boxlang.runtime.BoxRunner";

		var i               = 0;
		var originalCommand = commandService
			.getCallStack()
			.first()
			.commandInfo
			.ORIGINALLINE
			.replace( "boxlang cli", "" );
		cmd &= " " & originalCommand;

		print.toConsole();
		var output = command( "run" )
			.params( cmd )
			// Try to contain the output if we're in an interactive job and there are arguments (no args opens the boxlang shell)
			.run(
				echo         = verbose,
				returnOutput = ( job.isActive() && arguments.count() )
			);

		if ( job.isActive() && arguments.count() ) {
			print.text( output );
		}
	}

	private function getJarPath(){
		var localBoxlangJarPath = getSystemSetting( "BOXLANG_JAR_PATH", "" );
		if ( len( localBoxlangJarPath ) ) {
			return localBoxlangJarPath;
		}

		var jarInstallDir = expandPath( "/commandbox-boxlang/lib/boxlang/" );

		if ( len( moduleSettings.CLIBoxLangVersion ?: "" ) ) {
			var boxLangVersion = moduleSettings.CLIBoxLangVersion;
		} else {
			param server.checkedBoxLangLatestVersion = false;

			// TODO: setting to override version
			if ( !server.checkedBoxLangLatestVersion ) {
				var boxlangLatestVersion = getBoxLangLatestVersion()
			} else {
				var stableLocalVersions = directoryList( path = jarInstallDir )
					.map( ( d ) => d.listLast( "\/" ).replace( "boxlang-", "" ) )
					.filter( ( v ) => !semanticVersion.isPreRelease( v ) )
					.sort( ( a, b ) => semanticVersion.compare(
						b.listLast( "\/" ),
						a.listLast( "\/" )
					) )

				if ( stableLocalVersions.len() ) {
					var boxlangLatestVersion = stableLocalVersions.first();
				} else {
					var boxlangLatestVersion = getBoxLangLatestVersion()
				}
			}

			var boxLangVersion = boxlangLatestVersion;
		}
		var boxlangFileName     = "boxlang-#boxLangVersion#.jar";
		var boxlangDownloadURL  = "https://downloads.ortussolutions.com/ortussolutions/boxlang/#urlEncode( boxLangVersion )#/#urlEncode( boxlangFileName )#";
		var localBoxlangJarPath = "#jarInstallDir#/boxlang-#boxLangVersion#/#boxlangFileName#";
		var verbose             = moduleSettings.CLIVerbose ?: false;
		if ( !fileExists( localBoxlangJarPath ) ) {
			if ( verbose ) print.line( "Downloading BoxLang jar [#boxlangVersion#]..." );
			packageService.installPackage(
				ID        = "jar:#boxlangDownloadURL#",
				directory = jarInstallDir,
				save      = false,
				verbose   = verbose
			);
		}
		return localBoxlangJarPath;
	}

	function getBoxLangLatestVersion(){
		// This is the CF engine package, but it has the same versions
		var boxlangLatestVersion = endpointService
			.getEndpoint( "forgebox" )
			.getForgeBox()
			.getEntry( "boxlang" )
			.versions
			.filter( ( v ) => !semanticVersion.isPreRelease( v.version ) )
			.sort( ( a, b ) => semanticVersion.compare( b.version, a.version ) )
			.first()
			.version;

		var semverParsedVersion            = semanticVersion.parseVersion( boxlangLatestVersion );
		// reassemble without build number
		boxlangLatestVersion               = "#semverParsedVersion.major#.#semverParsedVersion.minor#.#semverParsedVersion.revision#";
		server.checkedBoxLangLatestVersion = true;
		return boxlangLatestVersion;
	}

	private function setBoxlangHomeToServer(){
		var systemSettings = wirebox.getInstance( "SystemSettings" );
		var configService  = wirebox.getInstance( "ConfigService" );
		var serverService  = wirebox.getInstance( "ServerService" );
		var shell          = wirebox.getInstance( "Shell" );

		var boxLangHome = "";

		// Get environment variables and server information
		var serverInfo                    = {};
		var interceptData_serverInfo_name = systemSettings.getSystemSetting( "interceptData.SERVERINFO.name", "" );

		// Strategy 1: Check if we're in single server mode
		if ( configService.getSetting( "server.singleServerMode", false ) && serverService.getServers().count() ) {
			serverInfo  = serverService.getFirstServer();
			boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
			// Strategy 2: Use server specified in environment variable
		} else if ( interceptData_serverInfo_name != "" ) {
			serverInfo = serverService.getServerInfoByName( interceptData_serverInfo_name );
			// Validate that the specified server is actually a BoxLang server
			if ( !( serverInfo.CFengine contains "boxlang" ) ) {
				return;
			}
			boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
		} else {
			// Strategy 3: Search for BoxLang server matching current working directory
			var webroot = fileSystemUtil.resolvePath( shell.getPWD() );
			var servers = serverService.getServers();
			for ( var serverID in servers ) {
				var thisServerInfo = servers[ serverID ];
				if (
					fileSystemUtil.resolvePath(
						path           = thisServerInfo.webroot,
						forceDirectory = true
					) == webroot
					&& thisServerInfo.CFengine contains "boxlang"
				) {
					serverInfo  = thisServerInfo;
					boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
					break;
				}
			}
			// Fallback: resolve server details for current directory
			if ( !serverInfo.count() ) {
				var serverDetails = serverService.resolveServerDetails( {} );
				serverInfo        = serverDetails.serverInfo;
				if ( !serverDetails.serverIsNew && ( serverInfo.CFengine contains "boxlang" ) ) {
					boxLangHome = serverInfo.serverHomeDirectory & "/WEB-INF/boxlang/";
				}
			}
		}
		if ( boxLangHome != "" ) {
			// Set BOXLANG_HOME environment variable
			systemSettings.setSystemSetting( "BOXLANG_HOME", boxLangHome );
			print.greenLine( "Set BOXLANG_HOME to [#boxLangHome#] for BoxLang CLI execution." ).toConsole();
			var WEBINFJarDir        = boxLangHome & "../lib/";
			var localBoxlangJarPath = "";
			var jars                = directoryList(
				path   = WEBINFJarDir,
				filter = "*.jar"
			);
			for ( var jar in jars ) {
				if ( jar contains "boxlang" ) {
					localBoxlangJarPath = getCanonicalPath( jar );
					break;
				}
			}
			if ( len( localBoxlangJarPath ) ) {
				print.greenLine( "Using BoxLang jar [#localBoxlangJarPath#]" ).toConsole();
				// Add in the runwar jar from the server using the path class path separator
				localBoxlangJarPath = localBoxlangJarPath & server.separator.path & serverInfo.runwarJarPath;
				systemSettings.setSystemSetting(
					"BOXLANG_JAR_PATH",
					localBoxlangJarPath
				);
			}
		}
	}

	/**
	 * Locate an available Java executable on the host machine or CommandBox with version >= 21.
	 *
	 * Order of resolution:
	 * 1. CLIJavaHome module setting or BOXLANG_JAVA_HOME / JAVA_HOME environment variable
	 * 2. Host system PATH
	 * 3. CommandBox host JVM
	 * 4. CommandBox downloaded serverJREs (javaService.listJavaInstalls())
	 * 5. Download openjdk21 via javaService.getJavaInstallPath() as fallback
	 *
	 * @verbose Whether to output detailed resolution messages
	 * @return Full path to the java executable
	 */
	private string function locateJavaBinary( boolean verbose = false ){
		var isWindows = fileSystemUtil.isWindows();
		var javaExe   = isWindows ? "java.exe" : "java";

		// 1. Check explicit setting or environment variable overrides
		var overrideHome   = moduleSettings.CLIJavaHome ?: "";
		var overrideSource = "module setting CLIJavaHome";
		if ( !len( overrideHome ) ) {
			overrideHome = getSystemSetting( "BOXLANG_JAVA_HOME", "" );
			if ( len( overrideHome ) ) {
				overrideSource = "environment variable BOXLANG_JAVA_HOME";
			}
		}
		// JAVA_HOME is a generic fallback, so skip it silently when it isn't usable
		var overrideIsFallback = false;
		if ( !len( overrideHome ) ) {
			overrideHome = getSystemSetting( "JAVA_HOME", "" );
			if ( len( overrideHome ) ) {
				overrideSource     = "environment variable JAVA_HOME";
				overrideIsFallback = true;
			}
		}

		if ( len( overrideHome ) ) {
			var overrideCandidate = trim( overrideHome );
			if ( !overrideCandidate.endsWith( "/" ) && !overrideCandidate.endsWith( "\" ) ) {
				overrideCandidate &= "/";
			}
			overrideCandidate &= "bin/" & javaExe;
			if ( fileExists( overrideCandidate ) ) {
				overrideCandidate = getCanonicalPath( overrideCandidate );
				var overrideMajor = getJavaMajorVersion( overrideCandidate );
				if ( overrideMajor >= 21 ) {
					if ( arguments.verbose ) {
						print.line( "Using Java from #overrideSource# [#overrideCandidate#] (version #overrideMajor#)" );
					}
					return overrideCandidate;
				} else if ( arguments.verbose && !overrideIsFallback ) {
					print.line( "Java override [#overrideCandidate#] is version [#overrideMajor#], but BoxLang requires Java 21+." );
				}
			}
		}

		// 2. Check host system PATH
		var pathCandidates = findJavaInPath();
		for ( var candidate in pathCandidates ) {
			var majorVersion = getJavaMajorVersion( candidate );
			if ( majorVersion >= 21 ) {
				if ( arguments.verbose ) {
					print.line( "Found Java on host PATH at [#candidate#] (version #majorVersion#)" );
				}
				return candidate;
			}
		}

		// 3. Check CommandBox's current JVM
		try {
			var currentJava = fileSystemUtil.getJREExecutable();
			if ( fileExists( currentJava ) ) {
				var currentMajor = getJavaMajorVersion( currentJava );
				if ( currentMajor >= 21 ) {
					if ( arguments.verbose ) {
						print.line( "Using CommandBox host JVM at [#currentJava#] (version #currentMajor#)" );
					}
					return currentJava;
				}
			}
		} catch ( any e ) {
			logger.error(
				"Error checking CommandBox host JRE: #e.message#",
				e
			);
		}

		// 4. Check CommandBox cached/downloaded serverJREs
		var javaVersion    = "openjdk21";
		var availableJavas = javaService
			.listJavaInstalls()
			.filter( ( jInstall ) => jInstall contains javaVersion )
			.map( ( name, deets ) => {
				deets.justJavaVersion = name.listLast( "-" );
				return deets;
			} )
			.valueArray()
			.sort( ( a, b ) => semanticVersion.compare( b.justJavaVersion, a.justJavaVersion ) );

		if ( availableJavas.len() ) {
			var thisJava       = availableJavas.first();
			var cachedJavaPath = thisJava.directory & "/" & thisJava.name & "/bin/" & javaExe;
			if ( fileExists( cachedJavaPath ) ) {
				if ( arguments.verbose ) {
					print.line( "Using CommandBox cached Java at [#cachedJavaPath#]" );
				}
				return cachedJavaPath;
			}
		}

		// 5. Fallback: Download OpenJDK 21 via CommandBox JavaService
		if ( arguments.verbose ) {
			print.line( "No Java 21+ found on host or cache. Downloading OpenJDK 21..." );
		}
		var downloadPath = javaService.getJavaInstallPath( javaVersion, arguments.verbose );
		return downloadPath & "/bin/" & javaExe;
	}

	/**
	 * Determine the major version of a Java executable binary.
	 *
	 * @javaBin Full path to the java executable
	 * @return Numeric major version (e.g. 21, 17, 8) or 0 if unable to detect
	 */
	private numeric function getJavaMajorVersion( required string javaBin ){
		var output = "";
		try {
			output = command( "run" ).params( """#arguments.javaBin#"" -version" ).run( returnOutput = true );
		} catch ( any e ) {
			logger.error(
				"Error checking Java version for [#arguments.javaBin#]: #e.message#",
				e
			);
			return 0;
		}

		if ( !len( trim( output ) ) ) {
			return 0;
		}

		// Look for version pattern: version "21.0.12.1", version "21", version "1.8.0_351"
		var versionSearch = output.reFindNoCase(
			"version\s+""([0-9]+)(\.([0-9]+))?",
			1,
			true
		);
		if ( versionSearch.pos[ 1 ] && versionSearch.match.len() > 1 ) {
			var major = val( versionSearch.match[ 2 ] );
			// Handle legacy 1.8.x versioning where major is 8
			if ( major == 1 && versionSearch.match.len() > 3 ) {
				major = val( versionSearch.match[ 4 ] );
			}
			return major;
		}

		// Fallback: look for first quoted version string like "21.0.1"
		var fallbackSearch = output.reFindNoCase( """([0-9]+(\.[0-9]+)*)""", 1, true );
		if ( fallbackSearch.pos[ 1 ] && fallbackSearch.match.len() > 1 ) {
			var versionStr = fallbackSearch.match[ 2 ];
			var firstNum   = val( versionStr.listGetAt( 1, "." ) );
			if ( firstNum == 1 && versionStr.listLen( "." ) > 1 ) {
				return val( versionStr.listGetAt( 2, "." ) );
			}
			return firstNum;
		}

		return 0;
	}

	/**
	 * Find unique executable Java binaries from the host system PATH.
	 *
	 * @return Array of canonical paths to java binaries
	 */
	private array function findJavaInPath(){
		var results   = [];
		var seen      = {};
		var isWindows = fileSystemUtil.isWindows();
		var javaExe   = isWindows ? "java.exe" : "java";
		var pathSep   = isWindows ? ";" : ":";
		var rawPath   = getSystemSetting( "PATH", "" );

		var pathDirs = listToArray( rawPath, pathSep );
		for ( var dir in pathDirs ) {
			var candidatePath = trim( dir ) & "/" & javaExe;
			try {
				if ( fileExists( candidatePath ) && ( getFileInfo( candidatePath ).canExecute ?: true ) ) {
					var canonical = getCanonicalPath( candidatePath );
					if ( !seen.keyExists( canonical ) ) {
						seen[ canonical ] = true;
						results.append( canonical );
					}
				}
			} catch ( any e ) {
				logger.error(
					"Error checking candidate Java path [#candidatePath#]: #e.message#",
					e
				);
			}
		}

		// Fallback to which / where command if PATH scan yielded no results
		if ( !results.len() ) {
			try {
				var lookupCmd    = isWindows ? "where.exe java" : "which java";
				var lookupOutput = command( "run" ).params( lookupCmd ).run( returnOutput = true );
				for (
					var line in listToArray(
						trim( lookupOutput ),
						chr( 10 ) & chr( 13 )
					)
				) {
					var trimmedLine = trim( line );
					if ( len( trimmedLine ) && fileExists( trimmedLine ) ) {
						var canonical = getCanonicalPath( trimmedLine );
						if ( !seen.keyExists( canonical ) ) {
							seen[ canonical ] = true;
							results.append( canonical );
						}
					}
				}
			} catch ( any e ) {
				logger.error(
					"Error resolving java executable via [#lookupCmd#]: #e.message#",
					e
				);
			}
		}

		return results;
	}

}
