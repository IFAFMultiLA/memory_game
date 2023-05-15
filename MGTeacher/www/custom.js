var stage_timer_interval = null;

function formatTimedelta(delta) {
    let delta_s = Math.round(delta / 1000);
    let m = Math.floor(delta_s / 60);
    let s = Math.round(delta_s - m * 60);

    return new String(m).padStart(2, "0") + ":" + new String(s).padStart(2, "0");
}

function updateStageTimer() {
    let timer = $("#stage_timer");
    let stage_timer_intro = $("#stage_timer_intro");

    if ($("#current_stage").text() == "end") {
        if (stage_timer_interval !== null) {
            clearInterval(stage_timer_interval);
            stage_timer_interval = null;
        }

        timer.hide();
        stage_timer_intro.hide();

        return
    }

    timer.show();
    stage_timer_intro.show();

    let t = Date.parse($("#stage_timestamp").text());
    timer.text(formatTimedelta(Date.now() - t));
}

$(document).on("shiny:connected", function() {
    stage_timer_interval = setInterval(updateStageTimer, 500);

    Shiny.addCustomMessageHandler("session_advanced", function(message) {
        if (stage_timer_interval === null) {
            stage_timer_interval = setInterval(updateStageTimer, 500);
        }
    });
});
