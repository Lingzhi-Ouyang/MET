package org.disalg.met.server.executor;

import org.disalg.met.api.MessageType;
import org.disalg.met.api.SubnodeState;
import org.disalg.met.api.SubnodeType;
import org.disalg.met.api.TestingDef;
import org.disalg.met.api.state.LeaderElectionState;
import org.disalg.met.server.TestingService;
import org.disalg.met.server.event.LocalEvent;
import org.disalg.met.server.state.Subnode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.util.Map;

/***
 * Executor of local event
 */
public class LocalEventExecutor extends BaseEventExecutor{
    private static final Logger LOG = LoggerFactory.getLogger(LocalEventExecutor.class);

    private final TestingService testingService;

    public LocalEventExecutor(final TestingService testingService) {
        this.testingService = testingService;
    }

    @Override
    public boolean execute(final LocalEvent event) throws IOException {
        if (event.isExecuted()) {
            LOG.info("Skipping an executed local event: {}", event.toString());
            return false;
        }
        LOG.debug("Processing request: {}", event.toString());
        releaseLocalEvent(event);
        testingService.getControlMonitor().notifyAll();
        testingService.waitAllNodesSteady();
        event.setExecuted();
        LOG.debug("Local event executed: {}\n\n\n", event.toString());
        return true;
    }

    // Should be called while holding a lock on controlMonitor
    /***
     * For sync
     * set SYNC_PROCESSOR / COMMIT_PROCESSOR to PROCESSING
     * @param event
     */
    public void releaseLocalEvent(final LocalEvent event) {
        testingService.setMessageInFlight(event.getId());
        SubnodeType subnodeType = event.getSubnodeType();

        final int subnodeId = event.getSubnodeId();
        final Subnode subnode = testingService.getSubnodes().get(subnodeId);
        final int nodeId = subnode.getNodeId();

        // set the corresponding subnode to be PROCESSING
        subnode.setState(SubnodeState.PROCESSING);

        if (event.getFlag() == TestingDef.RetCode.EXIT) {
            return;
        }

        // set the next subnode to be PROCESSING
        switch (subnodeType) {
            case QUORUM_PEER: // for FollowerProcessSyncMessage && LeaderJudgingIsRunning
                LeaderElectionState role = testingService.getLeaderElectionState(nodeId);
                if (role.equals(LeaderElectionState.FOLLOWING)) {
                    // for FollowerProcessSyncMessage: wait itself to SENDING state since ACK_NEWLEADER will come later anyway
                    // for FollowerProcessCOMMITInSync:
                    // FollowerProcessPROPOSALInSync:
                    int eventType = event.getType();
                    if (eventType == MessageType.DIFF || eventType == MessageType.TRUNC || eventType == MessageType.SNAP) {
                        testingService.getSyncTypeList().set(event.getNodeId(), event.getType());
                    }
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeInSendingState(testingService.getFollowerLearnerHandlerSenderMap(nodeId));
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeInSendingState(testingService.getFollowerLearnerHandlerMap(nodeId));
                }
                break;
            case SYNC_PROCESSOR:
                final Long zxid = event.getZxid();
                Map<Long, Integer> zxidSyncedMap = testingService.getZxidSyncedMap();
                testingService.getZxidSyncedMap().put(zxid, zxidSyncedMap.getOrDefault(zxid, 0) + 1);

//                 intercept log event and ack event
//                 leader will ack self, which is not intercepted
//                 follower will send ACK message to leader, which is intercepted only in follower
                LOG.debug("wait follower {}'s SYNC thread be SENDING ACK", event.getNodeId());
                if (LeaderElectionState.FOLLOWING.equals(testingService.getLeaderElectionState(nodeId))
                        && event.getFlag() != TestingDef.RetCode.NO_WAIT) {
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeInSendingState(subnodeId); // this is just for follower
                }
                break;
            case COMMIT_PROCESSOR:
                testingService.getControlMonitor().notifyAll();
                testingService.waitCommitProcessorDone(event.getId(), event.getNodeId());
                break;
        }
    }
}
