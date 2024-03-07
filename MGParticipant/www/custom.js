/**
 * Shrager Memory Game – participants' app: additional JavaScript code.
 *
 * Requires the Cookie object from the cookie.js library.
 *
 * Author: Markus Konrad <markus.konrad@htw-berlin.de>
 */

var sess_id = null;     // current session ID
var user_id = null;     // current user ID
var assignments = {};   // group assignments per session ID; session ID => group

// function that is called once the Shiny app is ready; sets up several listeners for custom messages that are sent
// from the Shiny side
$(document).on("shiny:connected", function() {
    // handle setting session ID
    Shiny.addCustomMessageHandler("set_sess_id", function(sess_id_from_shiny) {
        console.log("sess_id:", sess_id_from_shiny);
        sess_id = sess_id_from_shiny;

        if (Cookies.get("user_id") !== undefined) {
            // we already have a user ID stored in the cookie
            user_id = atob(Cookies.get("user_id"));
            console.log("user_id from cookies:", user_id);

            Shiny.setInputValue("user_id", user_id);
        } else {
            // no user ID yet; will be generated on Shiny side
            Shiny.setInputValue("user_id", "unassigned");
        }

        if (Cookies.get("assignments") !== undefined) {
            // group assignments are already stored in the cookie
            assignments = $.parseJSON(atob(Cookies.get("assignments")));
            console.log("assigments from cookies:", assignments);
        }

        if (assignments.hasOwnProperty(sess_id)) {
            // group assignment for this session already exists; send it to the Shiny side
            let group = assignments[sess_id];
            console.log("sending group assignment to Shiny:", group);
            Shiny.setInputValue("group", group);
        } else {
            // no group assignment for this session, yet; will be generated on Shiny side
            console.log("no group assignment, yet");
            assignments[sess_id] = null;
            Shiny.setInputValue("group", "unassigned");
        }
    });

    // handle setting user ID
    Shiny.addCustomMessageHandler("set_user_id", function(user_id_from_shiny) {
        console.log("got user ID from Shiny:", user_id_from_shiny);
        user_id = user_id_from_shiny;
        Cookies.set("user_id", btoa(user_id));  // also store user ID in cookie
    });

    // handle setting group assignment
    Shiny.addCustomMessageHandler("set_group", function(group) {
        if (sess_id === null) {
            console.error("session ID is null");
            return;
        }

        console.log("got group assignment from Shiny:", group);
        assignments[sess_id] = group;
        Cookies.set("assignments", btoa(JSON.stringify(assignments)));  // also store group assignment in cookie
    });

    // handle automatic submission of a form with submit button `btn_id`
    Shiny.addCustomMessageHandler("autosubmit", function(btn_id) {
        console.log("autosubmit", btn_id);

        $("#" + btn_id).click();
    });
});
