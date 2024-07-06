using Toybox.Application;
using Toybox.Lang;
using Toybox.Time;

var dexData;

(:typecheck(false) :background)
class ActiveLookDataFieldApp extends Application.AppBase {

    var inBackground = false;

    function initialize() {
        System.println("initiating dexData");
        dexData = new DexcomData();
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
        if(!inBackground) {Background.deleteTemporalEvent();}
    }

    //! Return the initial view of your application here
    function getInitialView() {
        
        //! trigger an event that executes the background task every five minutes 
        var FIVE_MINS = new Time.Duration(5 * 60);
        if (Toybox.System has :ServiceDelegate) {
            Background.registerForTemporalEvent(FIVE_MINS);
    	}
        
        return [ new ActiveLookDataFieldView() ];
    }

    //! Get a service delegate to run the background task
    function getServiceDelegate(){
        inBackground=true;
        return [new dexDFBG()];
    }

    //! Handle the data returned from the Dex background task 
    function onBackgroundData(data as Null or Lang.Dictionary or Lang.String) {
        System.println("in onBackgroundData: data = " + data); //! debug
        
        if (data != null) {
            dexData.responseCode = (data[(data.size()-1)]["ResponseCode"]).toNumber();
        
            if (dexData.responseCode == 200) {
                dexData.parseData(data);
            } else {
                Application.Properties.setValue("SessionID", null); 
            }
        }
        dexData.print();  //! debug
        data = null; //! saving memory?
    }
}
