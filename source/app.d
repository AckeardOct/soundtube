module app;

import vibe.d;

import std.stdio;
import std.file;
import std.process;
import std.datetime;
import std.conv;
import std.string;

struct Config
{
	short port = 8080;
	string rootDir = "public/";

	shared string toString() {
		string ret = "Config {";
		ret ~= "\n    port: " ~ to!string(port);
		ret ~= "\n    rootDir: " ~ rootDir;
		ret ~= "\n};";
		return ret;
	}
}

shared Config CFG;

class VideoProcessor
{
	private {
		string outputPath;
		File output;
		Pid pid;
		string audioFilePath;
		string lastInfo;
	}

	this(string link)
	{		
		outputPath = std.file.deleteme();
		output = File(outputPath, "w");		
		audioFilePath = "/audios/" ~ Clock.currTime().toISOExtString() ~ ".mp3";		
		pid = spawnShell("youtube-dl " ~ link ~ " -x --audio-format mp3 -o " ~ CFG.rootDir ~ audioFilePath, stdin, output);
	}

	~this()
	{		
		std.file.remove(outputPath);		
	}

	string getOutput()
	{		
		string ret = readText(outputPath);		
		ulong cut = lastIndexOf(ret, '[');
		if(cut > 0 && ret.length > 0)	
			ret = ret[cut .. $];

		lastInfo = ret;
		return ret;
	}

	pure string getAudioPath() { return audioFilePath; }
	pure string getLastInfo() { return lastInfo; }

	bool isStoped() { return tryWait(pid).terminated; }
}

// The methods of this class will be mapped to HTTP routes and serve as
// request handlers.
class SampleService 
{
	private VideoProcessor videoProcessor;

	// overrides the path that gets inferred from the method name to
	// "GET /"
	@path("/") void getHome()
	{				
		render!("home.dt");
	}
	// GET /sound
	void getStart(string str)
	{						
		if(!videoProcessor) {
			logInfo("Start processing: " ~ str);			
			videoProcessor = new VideoProcessor(str);
		}
	}

	void getInform()
	{				
		if(videoProcessor)
		{
			string link;
			string text;
			if(!videoProcessor.isStoped)
				text = videoProcessor.getOutput();
			else {
				text = videoProcessor.getLastInfo();
				link = videoProcessor.getAudioPath();
				delete videoProcessor;
			}
			render!("info.dt", text, link);
		}
	}

	// Adds support for using private member functions with "before". The ensureAuth method
	// is only used internally in this class and should be private, but by default external
	// template code has no access to private symbols, even if those are explicitly passed
	// to the template. This mixin template defined in vibe.web.web creates a special class
	// member that enables this usage pattern.
	mixin PrivateAccessProxy;
}

shared static this()
{
	readOption("p", cast(short*) &CFG.port, "Port {default 8080}");
	readOption("r", cast(string*) &CFG.rootDir, "Root directory for static files {default public/}");

	// Create the router that will dispatch each request to the proper handler method
	auto router = new URLRouter;
	// Register our sample service class as a web interface. Each public method
	// will be mapped to a route in the URLRouter
	router.registerWebInterface(new SampleService);
	// All requests that haven't been handled by the web interface registered above
	// will be handled by looking for a matching file in the public/ folder.
	//router.get("*", serveStaticFiles("public/"));
	router.get("*", serveStaticFiles(CFG.rootDir));

	// Start up the HTTP server
	auto settings = new HTTPServerSettings;
	settings.port = CFG.port;	
	settings.sessionStore = new MemorySessionStore;
	listenHTTP(settings, router);
	
	logInfo(CFG.toString());
}
