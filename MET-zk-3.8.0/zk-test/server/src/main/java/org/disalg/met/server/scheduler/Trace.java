package org.disalg.met.server.scheduler;

import com.alibaba.fastjson.JSONArray;
import com.alibaba.fastjson.JSONObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;

public class Trace {

    private static final Logger LOG = LoggerFactory.getLogger(Trace.class);

    private final String traceName;
    private final JSONArray executionSteps = new JSONArray();
    private int currentIdx;
    private int stepCount;
    private int serverNum;
    private List<String> serverIds;

    public Trace(String traceName, int serverNum, List<String> serverIds, JSONArray jsonArray) {
        this.traceName = traceName;
        this.serverNum = serverNum;
        this.serverIds = serverIds;
        this.currentIdx = -1;
        this.stepCount = jsonArray.size();
        LOG.debug("stepCount: " + stepCount);
        this.executionSteps.addAll(jsonArray);
    }

    public String getTraceName() {
        return traceName;
    }

    public int getServerNum() {
        return serverNum;
    }

    public List<String> getServerIds() {
        return serverIds;
    }

    public int getStepCount() {
        return stepCount;
    }

    public void setStepCount(int stepCount) {
        this.stepCount = stepCount;
    }

    public void addSteps(JSONArray eventList) {
        executionSteps.addAll(eventList);
    }

    public void addStep(String event) {
        executionSteps.add(event);
        stepCount++;
    }

    public JSONObject nextStep() {
        this.currentIdx++;
        LOG.debug("currentIdx: " + currentIdx + ", stepCount: " + stepCount);
        assert currentIdx < stepCount;
        return (JSONObject) executionSteps.get(currentIdx);
    }

    public JSONObject getStep(int idx) {
        this.currentIdx = idx;
        LOG.debug("step: " + (currentIdx+1) + ", currentIdx: " + currentIdx + ", stepCount: " + stepCount);
        assert currentIdx < stepCount;
        return (JSONObject) executionSteps.get(currentIdx);
    }



    @Override
    public String toString() {
        return "Trace{" +
                "traceName='" + traceName + '\'' +
                ", executionSteps=" + executionSteps +
                ", currentIdx=" + currentIdx +
                ", stepCount=" + stepCount +
                '}';
    }
}
