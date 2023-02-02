package org.disalg.met.server.predicate;

import org.disalg.met.api.NodeState;
import org.disalg.met.server.TestingService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class CurrentEpochFileUpdated implements WaitPredicate{
    private static final Logger LOG = LoggerFactory.getLogger(CurrentEpochFileUpdated.class);

    private final TestingService testingService;

    private final int nodeId;
    private final long lastCurrentEpoch;

    public CurrentEpochFileUpdated(final TestingService testingService,
                                   final int nodeId,
                                   final long lastCurrentEpoch) {
        this.testingService = testingService;
        this.nodeId = nodeId;
        this.lastCurrentEpoch = lastCurrentEpoch;
    }

    @Override
    public boolean isTrue() {
        return testingService.getCurrentEpoch(nodeId) > lastCurrentEpoch
                || NodeState.STOPPING.equals(testingService.getNodeStates().get(nodeId));
    }

    @Override
    public String describe() {
        return "currentEpoch file of " + nodeId + " updated";
    }
}
