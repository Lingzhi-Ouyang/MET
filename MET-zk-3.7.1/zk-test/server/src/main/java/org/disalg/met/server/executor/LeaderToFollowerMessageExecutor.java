package org.disalg.met.server.executor;

import org.disalg.met.api.*;
import org.disalg.met.server.TestingService;
import org.disalg.met.server.event.LeaderToFollowerMessageEvent;
import org.disalg.met.server.state.Subnode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;

public class LeaderToFollowerMessageExecutor extends BaseEventExecutor {

    private static final Logger LOG = LoggerFactory.getLogger(LeaderToFollowerMessageExecutor.class);

    private final TestingService testingService;

    public LeaderToFollowerMessageExecutor(final TestingService testingService) {
        this.testingService = testingService;
    }

    @Override
    public boolean execute(final LeaderToFollowerMessageEvent event) throws IOException {
        if (event.isExecuted()) {
            LOG.info("Skipping an executed learner handler message event: {}", event.toString());
            return false;
        }
        LOG.debug("Releasing leader message: {}", event.toString());
        releaseLeaderToFollowerMessage(event);
        testingService.getControlMonitor().notifyAll();
        testingService.waitAllNodesSteady();
        event.setExecuted();
        LOG.debug("Learner handler message executed: {}\n\n\n", event.toString());
        return true;
    }

    /***
     * From leader to follower
     * set sendingSubnode and receivingSubnode SYNC_PROCESSOR / COMMIT_PROCESSOR to PROCESSING
     */
    public void releaseLeaderToFollowerMessage(final LeaderToFollowerMessageEvent event) {
        testingService.setMessageInFlight(event.getId());
        final int sendingSubnodeId = event.getSendingSubnodeId();
        final Subnode sendingSubnode = testingService.getSubnodes().get(sendingSubnodeId);

        // set the sending subnode to be PROCESSING
        sendingSubnode.setState(SubnodeState.PROCESSING);

        if (event.getFlag() == TestingDef.RetCode.EXIT) {
            return;
        }

        // if in partition, then just drop it
        final int leaderId = sendingSubnode.getNodeId();
        final int followerId = event.getReceivingNodeId();
        LOG.debug("partition map: {}, leader: {}, follower: {}", testingService.getPartitionMap(), leaderId, followerId);
        if (testingService.getPartitionMap().get(leaderId).get(followerId) ||
            event.getFlag() == TestingDef.RetCode.NODE_PAIR_IN_PARTITION) {
            return;
        }

        // not in partition, so the message can be received
        // set the receiving subnode to be PROCESSING
        final int type = event.getType();
        final NodeState followerState = testingService.getNodeStates().get(followerId);

        // release the leader's message,
        // and then wait for the target follower to be at the next intercepted point
        if (NodeState.ONLINE.equals(followerState)) {
            switch (type) {
                case MessageType.LEADERINFO:
                    LOG.info("leader releases LEADERINFO and follower will reply ACKEPOCH: {}", event);
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeTypeSending(followerId, SubnodeType.QUORUM_PEER);
                    break;
                case MessageType.DIFF:
                case MessageType.TRUNC:
                case MessageType.SNAP:
                    LOG.info("leader sends DIFF / TRUNC / SNAP that follower will not reply : {}", event);
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeInSendingState(sendingSubnodeId);
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitFollowerMappingLearnerHandlerSender(followerId);
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeInSendingState(testingService.getFollowerLearnerHandlerMap(followerId));
                    break;
                case MessageType.NEWLEADER:
                    // wait for follower's ack to be sent.
                    // Before this done, follower's currentEpoch file is updated
                    LOG.info("leader releases NEWLEADER and follower will reply ACK: {}", event);
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeTypeSending(followerId, SubnodeType.QUORUM_PEER);

                    // let leader's corresponding learnerHandler be intercepted at ReadRecord
                    // Note: sendingSubnodeId is the learnerHandlerSender, not learnerHandler
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeInSendingState(testingService.getFollowerLearnerHandlerMap(followerId));

                    break;
                case MessageType.UPTODATE:
                    // We do not intercept ACK to UPTODATE
                    LOG.info("leader releases UPTODATE and follower will reply ACK: {}", event);
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeTypeSending(followerId, SubnodeType.QUORUM_PEER);

                    // let leader's corresponding learnerHandler be intercepted at ReadRecord
                    // Note: sendingSubnodeId is the learnerHandlerSender, not learnerHandler
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeInSendingState(testingService.getFollowerLearnerHandlerMap(followerId));

                    // let leader's QUORUM_PEER be intercepted at LeaderJudgeIsRunning
                    testingService.getControlMonitor().notifyAll();
                    testingService.waitSubnodeTypeSending(leaderId, SubnodeType.QUORUM_PEER);
                    break;
                case MessageType.PROPOSAL: // for leader's PROPOSAL in sync, follower will not produce any intercepted event
                    if (Phase.BROADCAST.equals(testingService.getNodePhases().get(followerId))) {
                        testingService.getControlMonitor().notifyAll();
                        testingService.waitSubnodeTypeSending(followerId, SubnodeType.SYNC_PROCESSOR);
                    }
                    break;
                case MessageType.COMMIT: // for leader's COMMIT in sync, follower will not produce any intercepted event
                    if (Phase.BROADCAST.equals(testingService.getNodePhases().get(followerId))) {
                        testingService.getControlMonitor().notifyAll();
                        testingService.waitSubnodeTypeSending(followerId, SubnodeType.COMMIT_PROCESSOR);
                    }
                    break;
                case TestingDef.MessageType.learnerHandlerReadRecord:
//                    if (Phase.SYNC.equals(testingService.getNodePhases().get(followerId))) {
//                        // must be going to send UPTODATE
//                        testingService.getControlMonitor().notifyAll();
//                        testingService.waitSubnodeInSendingState(testingService.getFollowerLearnerHandlerSenderMap(followerId));
//                    }
//                    LOG.info("release learner handler to read a message : {}", event);
//                    testingService.getControlMonitor().notifyAll();
//                    testingService.waitSubnodeInSendingState(sendingSubnodeId);
                    break;
                default:
                    LOG.info("leader sends a message : {}", event);
                    break;
            }
        }
    }
}
