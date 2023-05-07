using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Background;
using Toybox.Communications as Comms;

(:background)
class DexcomData {
    public var bg_mmol      as Lang.Float;
    public var bg_mgdl      as Lang.number;
    public var trend        as Lang.Number;
    public var sampleTime   as Time.Moment;
    public var responseCode as Lang.Number;
    
    private var _trends = {
	    "DoubleDown" => 7,
	    "SingleDown" => 6,
	    "FortyFiveDown" => 5,
	    "Flat"=> 4,
	    "FortyFiveUp" => 3,
	    "SingleUp" => 2,
	    "DoubleUp" => 1
    };
    
    public function initialize() {
        self.bg_mmol = 0.0;
        self.bg_mgdl = 0;
        self.trend = 0;
        self.sampleTime = null;
        self.responseCode = 0;
    }

    public function parseData(data as Null or Lang.Dictionary or Lang.String) {
        
        var _timeStr;
        var _elapsedMinutes;

        if (data != null) {
            //! Store sessionID and serverID in object store 
            Application.Properties.setValue("SessionID", data[(data.size()-1)]["SessionID"]); 
		    Application.Properties.setValue("Server", data[(data.size()-1)]["Server"]);

            //! Clear out old data
            initialize();

            if ((data.size()>0) && data[0].hasKey("Value") && data[0]["Value"] != null) { 
    			self.bg_mgdl = data[0]["Value"].toNumber();
    			self.bg_mmol = (self.bg_mgdl.toFloat() / 18).format("%.1f");	
    		}

            if ((data.size()>0) && data[0].hasKey("Trend") && data[0]["Trend"] != null) { 
    			self.trend = (data[0]["Trend"]).toNumber(); 
                if (self.trend == null && _trends.hasKey(data[0]["Trend"])) {
    			    self.trend =  _trends.get(data[0]["Trend"]);
    			}
    		}

            if ((data.size()>0) && data[0].hasKey("WT") && data[0]["WT"] != null) { 
				_timeStr = formatTimeStrSeconds(data[0]["WT"]);
                self.sampleTime = new Time.Moment(_timeStr.toNumber());
                
                //! used for debug
                _elapsedMinutes = Math.floor(Time.now().subtract(self.sampleTime).value() / 60);
                System.println("Elapsed Minutes = " + _elapsedMinutes);
    		}

			self.responseCode = (data[(data.size()-1)]["ResponseCode"]).toNumber();

        } else {
            Application.Properties.setValue("SessionID", null); 
        }
        data = null; //saving memory?
    }

    public function print(){
        var _info;
        var _timeStr;

        System.println("DexcomData:");
        System.println(" bg_mmol:      " + self.bg_mmol);
        System.println(" bg_mgdl:      " + self.bg_mgdl);
        System.println(" trend:        " + self.trend);
        System.println(" responseCode: " + self.responseCode);

        if (self.sampleTime != null) {
            _info = Gregorian.info(self.sampleTime, Time.FORMAT_SHORT);
            _timeStr = Lang.format("$1$-$2$-$3$ $4$:$5$:$6$", [_info.year, _info.month.format("%02d"), _info.day.format("%02d"), _info.hour.format("%02d"), _info.min.format("%02d"), _info.sec.format("%02d")]);
        } else {
            _timeStr = null;
        }
        System.println(" sampleTime:   " + _timeStr);
    }

    private function formatTimeStrSeconds(str) {
		var _digits = [ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' ];
		var _length = str.length() as Lang.Number;
		var i = 0 as Lang.Number;
		var x = 0 as Lang.Number;
		var _result ="" as Lang.String;	
		str = str.toCharArray();
			
		while (i < _length) {
			if(_digits.indexOf(str[i]) >= 0) {
				_result = _result+str[i];
				x++;
			}
			i++; 
		}
		return _result.substring(0, (_result.length()-3));
    }		 

}

(:background)
class dexDFBG extends Toybox.System.ServiceDelegate {

	var m_sessionID;
	var m_server;
	var m_password;
	var m_serverHostname = ""; 
	var m_username;
	var m_nrRetries = 0;
	
	const DexcomEUServer = 0;
	const DexcomUSServer = 1;

    function initialize() {
      System.ServiceDelegate.initialize();
	}
	

    function onTemporalEvent() {
        System.println("In onTemporalEvent"); //debug
        //Background.exit([{"Value"=>150, "Trend"=>"FortyFiveUp", "WT"=>"Date(1683371059000)", "DT"=>"Date(1683371059000+0200)", "ST"=>"Date(1683371059000)"}, {"ResponseCode"=>200, "Server"=>0, "SessionID"=>"0f94a39e-2fc8-4e1d-9911-1c5bf461d3a8"}]);

        m_nrRetries = 0;

        //! fetch dexcom serverID and sessionID from object store
		m_sessionID = (Application.getApp()).getProperty("SessionID");
		m_server = (Application.getApp()).getProperty("Server");
		if (m_server == null) {m_server = DexcomEUServer;}

        //! fetch dexcom username from object store
        //! if username has not been configured, omitt request.  
        m_username = (Application.getApp()).getProperty("Username");
        if (m_username != null && m_username.equals("dexcom_account")) {
			System.println("Dexcom username not configured, omitting request");
		} else {
            //if (m_sessionID == null || m_sessionID == "") {
            if (m_sessionID == null || m_sessionID.equals("")) {
				//! No valid dexcom SessionID, authenticate user 
                getDexcomID();
			} else {	
				//! Valid sessionID, request data from Dexcom
                readValue();
			}
		}
	}

    //! getDexcomID: Send a dexcom authentication request 
    function getDexcomID() {
		m_password = (Application.getApp()).getProperty("Password");
		
		//! Create the web request
        if (m_server.toNumber() == DexcomEUServer) {m_serverHostname = "shareous.dexcom.com";}
		else {m_serverHostname = "share1.dexcom.com";}
		
        var headers = { 
			"User-Agent" => "Dexcom%20Share/3.0.2.11 CFNetwork/711.2.23 Darwin/14.0.0",	
			"dexcom-account" => m_username,
			"dexcom-server" => m_serverHostname,
			"dexcom-app" => "ActiveLook DF",
			"Content-Type" => Comms.REQUEST_CONTENT_TYPE_JSON };
	
		var params = {
			"password" => m_password,
			"accountName" => m_username,
			"applicationId" => "d89443d2-327c-4a6f-89e5-496bbb0317db" };
		
		var options = { 
			:method => Comms.HTTP_REQUEST_METHOD_POST,
			:responseType => Comms.HTTP_RESPONSE_CONTENT_TYPE_JSON,
			:headers => headers };	
		
		var _loginURL = "";
			
		if (m_server.toNumber() == DexcomUSServer) {
			_loginURL = "https://dexauth-us.herokuapp.com/ShareWebServices/Services/General/AuthenticatePublisherAccount";
		}
		else { 
			_loginURL = "https://dexauth-eu.herokuapp.com/ShareWebServices/Services/General/AuthenticatePublisherAccount";
   		}	

		System.println("getID, URL: " + _loginURL + " params: " + params); // debug
        var callback =  method(:getIDResponse);
    	Comms.makeWebRequest(_loginURL, params, options, method(:getIDResponse));
    	
    	//optimize memory
    	headers = null; params = null; options = null; _loginURL = null;
	} 


    //! getIDResponse: callback function to recive the authentication request response
    function getIDResponse(responseCode as Lang.Number, data as Null or Lang.Dictionary or Lang.String) as Void {
        System.println("In getIDResponse: responseCode = " + responseCode + " data: " + data + " server: " + m_server);		// debug
					
		if ((responseCode == 200) && (data != null) && (data["ErrorCode"] == 200)) {
            m_nrRetries = 0;
			loginDexcom(data["SessionID"]);
			data = null; //optimize memory
		} else if ((responseCode != 200) && (m_nrRetries < 2)) {
			// try the other Dexcom server
			m_server = 1 - m_server.toNumber();
			m_nrRetries ++;
			data = null;
			getDexcomID();
		
		} else { 
    		m_sessionID = null;
    		data = null;
    		Background.exit([{},{"ResponseCode" => responseCode}]);
    	}
	}


    //!loginDexcom: use the authentication token to create a Dexcom session
    function loginDexcom(userID) {
		var headers = { 
			"User-Agent" => "Dexcom%20Share/3.0.2.11 CFNetwork/711.2.23 Darwin/14.0.0",	
			"dexcom-account" => m_username,
			"dexcom-server" => m_serverHostname,
			"dexcom-app" => "Dex DF",
			"Content-Type" => Comms.REQUEST_CONTENT_TYPE_JSON };
	
		var params = {
			"password" => m_password,
			"accountId" => userID,
			"applicationId" => "d89443d2-327c-4a6f-89e5-496bbb0317db" };
		
		var options = { 
			:method => Comms.HTTP_REQUEST_METHOD_POST,
			:responseType => Comms.HTTP_RESPONSE_CONTENT_TYPE_JSON,
			:headers => headers };	
    	
    	var _loginURL = "";
		var callback =  method(:loginResponse);

    	if (m_server.toNumber() == DexcomUSServer) {
    		_loginURL = "https://dexauth-us.herokuapp.com/ShareWebServices/Services/General/LoginPublisherAccountById";
    	} else {
    		_loginURL = "https://dexauth-eu.herokuapp.com/ShareWebServices/Services/General/LoginPublisherAccountById";
    	}
    	System.println("loginDexcom: URL: " + _loginURL + " params: " + params); // debug
    	Comms.makeWebRequest(_loginURL, params, options, method(:loginResponse));
    	
    	//optimize memory
    	headers = null; params = null; options = null; _loginURL = null;
	
	}    

    //! loginresponse: callback function to receive the login response
    function loginResponse(responseCode as Lang.Number, data as Null or Lang.Dictionary or Lang.String) as Void {
		System.println("In login_response: responseCode = " + responseCode + " data: " + data); // debug

		if ((responseCode == 200) && (data != null) && (data["ErrorCode"] == 200)) {
			m_sessionID = data["SessionID"];
			m_nrRetries = 0;
			data = null;
			readValue();
		} else { 
    		m_sessionID = null;
    		data = null;
    		Background.exit([{},{"ResponseCode" => responseCode}]);
    	}
	}

    //! readValue: Request blood glucose data from the Dexcom server
    function readValue() {
		var headers = { 
					"User-Agent" => "Dexcom%20Share/3.0.2.11 CFNetwork/711.2.23 Darwin/14.0.0",	
					"Content-Type" => Comms.REQUEST_CONTENT_TYPE_JSON, 
					"Content-Length" => "0" };	
    	
    	var options = { 
					:method => Comms.HTTP_REQUEST_METHOD_POST,
					:responseType => Comms.HTTP_RESPONSE_CONTENT_TYPE_JSON, 
					:headers => headers };
    	
    	var _readURL = "";
		var callback =  method(:readResponse);
    	if (m_server == DexcomUSServer) {
    		_readURL = "https://share1.dexcom.com/ShareWebServices/Services/Publisher/ReadPublisherLatestGlucoseValues" + "?sessionID=" + m_sessionID + "&minutes=" + 1440 + "&maxCount=" + 1;
    	} 
    	else {
    		_readURL = "https://shareous1.dexcom.com/ShareWebServices/Services/Publisher/ReadPublisherLatestGlucoseValues" + "?sessionID=" + m_sessionID + "&minutes=" + 1440 + "&maxCount=" + 1;
    	}
    	
        System.println("Read request: URL = " + _readURL); // debug
        Comms.makeWebRequest(_readURL, {}, options, method(:readResponse));	

		//optimize memory
    	headers = null; options = null; _readURL = null;

	}

    //! readResponse: callback function to receive the read request response from Dexcom
    function readResponse(responseCode , data) as Void {
	//function readResponse(responseCode as Lang.Number, data as Null or Lang.Dictionary or Lang.String) as Void {
    	System.println("in readResponse: data= " + data + " responseCode= " + responseCode);
    	if (responseCode == 200) {
    		//if (data.size() == 0) {responseCode = 204;}
    		data.add({"ResponseCode" => responseCode, "SessionID" => m_sessionID, "Server" => m_server});
			Background.exit(data);	

    	} else if ((responseCode == 500) && (m_nrRetries < 2)) { 
    		// reset sessionID to trigger a new authentication
    		m_nrRetries ++;
    		m_sessionID = null;
    		data = null;
    		getDexcomID();
    		
   		} else {
    		Background.exit([{},{"ResponseCode" => responseCode}]); //frsal
    	}
    }
    
}