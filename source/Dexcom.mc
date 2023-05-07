using Toybox.Lang;
using Toybox.Time;
using Toybox.Background;

(:background)
class DexcomData {
    public var bg_mmol      as Lang.Float;
    public var bg_mgdl      as Lang.number;
    public var trend        as Lang.Number;
    public var sampleTime   as Time.Moment;
    public var responseCode as Lang.Number;
    
    public function initialize() {
        self.bg_mmol = 0.0;
        self.bg_mgdl = 0;
        self.trend = 0;
        self.sampleTime = null;
        self.responseCode = 0;
    }

    public function parseData(data as Null or Lang.Dictionary or Lang.String) {
        
        if (data != null) {
            //! Store sessionID and serverID in object store 
            Application.Properties.setValue("SessionID", data[(data.size()-1)]["SessionID"]); 
		    Application.Properties.setValue("Server", data[(data.size()-1)]["Server"]);

            if ((data.size()>0) && data[0].hasKey("Value") && data[0]["Value"] != null) { 
    			self.bg_mgdl = data[0]["Value"].toNumber();
    			self.bg_mmol = (self.bg_mgdl.toFloat() / 18).format("%.1f");	
    		}

            if ((data.size()>0) && data[0].hasKey("Trend") && data[0]["Trend"] != null) { 
    			self.trend = (data[0]["Trend"]).toNumber();
    			
                // solve inconsistancy in trend reporting EU vs US
                //if (m_dexcomData["Trend"] == null && Trends.hasKey(data[0]["Trend"])) {
    			//	m_dexcomData["Trend"] =  Trends.get(data[0]["Trend"]);
    			//}
    			
    		}

            if ((data.size()>0) && data[0].hasKey("WT") && data[0]["WT"] != null) { 
				self.sampleTime = new Time.Moment(data[0]["WT"].toNumber());
                // verify if this actually works
    		}
        } else {
            Application.Properties.setValue("SessionID", null); 
        }
        System.println("in parseData: data = " + data); //debug 
        System.println("dexData: " + dexData); //debug
        data = null; //saving memory?
    }

    // remove?
    private function formatTimeStr(str) {
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
		return _result;
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
        System.println("In onTemporalEvent");
        Background.exit([{},{"ResponseCode" => 200}]);
    }
}