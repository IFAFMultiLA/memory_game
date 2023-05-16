var sess_id = null;
var user_id = null;
var assignments = {};

$(document).on("shiny:connected", function() {
    Shiny.addCustomMessageHandler("set_sess_id", function(sess_id_from_shiny) {
        console.log("sess_id:", sess_id_from_shiny);
        sess_id = sess_id_from_shiny;

        if (Cookies.get("user_id") !== undefined) {
            user_id = atob(Cookies.get("user_id"));
            console.log("user_id from cookies:", user_id);

            Shiny.setInputValue("user_id", user_id);
        } else {
            Shiny.setInputValue("user_id", "unassigned");
        }

        if (Cookies.get("assignments") !== undefined) {
            assignments = $.parseJSON(atob(Cookies.get("assignments")));
            console.log("assigments from cookies:", assignments);
        }

        if (assignments.hasOwnProperty(sess_id)) {
            let group = null;
            group = assignments[sess_id];
            console.log("sending group assignment to Shiny:", group);
            Shiny.setInputValue("group", group);
        } else {
            console.log("no group assignment, yet");
            assignments[sess_id] = null;
            Shiny.setInputValue("group", "unassigned");
        }
    });

    Shiny.addCustomMessageHandler("set_user_id", function(user_id_from_shiny) {
        console.log("got user ID from Shiny:", user_id_from_shiny);
        user_id = user_id_from_shiny;
        Cookies.set("user_id", btoa(user_id));
    });

    Shiny.addCustomMessageHandler("set_group", function(group) {
        if (sess_id === null) {
            console.error("session ID is null");
            return;
        }

        console.log("got group assignment from Shiny:", group);
        assignments[sess_id] = group;
        Cookies.set("assignments", btoa(JSON.stringify(assignments)));
    });
});
