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
            case QUORUM_PEER:
                // follower: FollowerProcessSyncMessage / FollowerProcessPROPOSALInSync
                //              / FollowerProcessCOMMITInSync / SubmitLoggingTaskInProcessingNEWLEADER
                // leader: LeaderJudgingIsRunning
                LeaderElectionState role = testingService.getLeaderElectionState(nodeId);
                if (role.equals(LeaderElectionState.FOLLOWING)) {
                    int eventType = event.getType();
                    if (eventType == TestingDef.MessageType.NEWLEADER) { // release FollowerProcessNEWLEADERAfterCurrentEpochUpdated
//                        //  Post-condition: FollowerSendACKtoNEWLEADER by follower's QUORUM_PEER
//                        testingService.getControlMonitor().notifyAll();
//                        testingService.waitSubnodeTypeSending(nodeId, SubnodeType.QUORUM_PEER);

                        // let leader's corresponding learnerHandler be intercepted at ReadRecord
                        testingService.getControlMonitor().notifyAll();
                        testingService.waitSubnodeInSendingState(testingService.getFollowerLearnerHandlerMap(nodeId));
                    }
                    else {
                        // TODO: deprecated since this branch will not be triggered!
                        LOG.warn("This branch is not supposed to occur!!! Local event: {}", event);
                        if (eventType == MessageType.DIFF || eventType == MessageType.TRUNC || eventType == MessageType.SNAP) {
                            testingService.getSyncTypeList().set(event.getNodeId(), event.getType());
                        }
                        // for FollowerProcessSyncMessage / FollowerProcessPROPOSALInSync / FollowerProcessCOMMITInSync:
                        //  Post-condition:  wait for the follower's QUORUM_PEER thread to SENDING state
                        //      since ACK_LD will come at last anyway
                        testingService.getControlMonitor().notifyAll();
                        testingService.waitSubnodeInSendingState(testingService.getFollowerLearnerHandlerSenderMap(nodeId));
                        testingService.getControlMonitor().notifyAll();
                        testingService.waitSubnodeInSendingState(testingService.getFollowerLearnerHandlerMap(nodeId));
                    }
                }
                break;
            case SYNC_PROCESSOR: // leader / follower do log
                final Long zxid = event.getZxid();
                Map<Long, Integer> zxidSyncedMap = testingService.getZxidSyncedMap();
                testingService.getZxidSyncedMap().put(zxid, zxidSyncedMap.getOrDefault(zxid, 0) + 1);

                // for log event and ack event
                // leader will ack self, which is not intercepted
                // follower will send ACK message to leader, which is intercepted only in follower
                LOG.debug("wait follower {}'s SYNC thread be SENDING ACK", event.getNodeId());
                if (LeaderElectionState.FOLLOWING.equals(testingService.getLeaderElectionState(nodeId))
                        && event.getFlag() != TestingDef.RetCode.NO_WAIT) {
                    // Post-condition: FollowerSendACKtoPROPOSAL by follower's SYNC_PROCESSOR
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeInSendingState(subnodeId); // this is just for follower
                }
                break;
            case COMMIT_PROCESSOR:  // leader / follower do commit
                // Post-condition: wait for the node update its lastProcessedZxid
                testingService.getControlMonitor().notifyAll();
                testingService.waitCommitProcessorDone(event.getId(), event.getNodeId());
                break;
        }
    }
}
