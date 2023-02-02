package org.apache.zookeeper.server.quorum;

import org.apache.jute.Record;
import org.disalg.met.api.SubnodeType;
import org.disalg.met.api.TestingDef;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.net.SocketTimeoutException;
import java.rmi.RemoteException;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.atomic.AtomicInteger;

/***
 * This intercepts the message sending process of the learnerHandler threads on the leader side
 */
public aspect LearnerHandlerAspect {

    private static final Logger LOG = LoggerFactory.getLogger(LearnerHandlerAspect.class);

    private final QuorumPeerAspect quorumPeerAspect = QuorumPeerAspect.aspectOf();

    private static Map<Long, Long> learnerHandlerSenderThreadMap = new HashMap<>(); // key: learnerHandlerThreadId, value: learnerHandlerSenderThreadId
    private static Map<Long, Long> learnerHandlerThreadMap = new HashMap<>(); // key: learnerHandlerSenderThreadId, value: learnerHandlerThreadId

    // Intercept starting the thread
    // This thread should only be run by the leader

    pointcut runLearnerHandler(): execution(* org.apache.zookeeper.server.quorum.LearnerHandler.run());

    before(): runLearnerHandler() {
        final long threadId = Thread.currentThread().getId();
        final String threadName = Thread.currentThread().getName();
        LOG.debug("before runLearnerHandler-------Thread: {}, {}------", threadId, threadName);
        QuorumPeerAspect.SubnodeIntercepter intercepter = quorumPeerAspect.registerSubnode(
                Thread.currentThread().getId(), Thread.currentThread().getName(), SubnodeType.LEARNER_HANDLER);
        // Set RECEIVING state since there is nowhere else to set
        int subnodeId = -1;
        try{
            subnodeId = intercepter.getSubnodeId();
        } catch (RuntimeException e) {
            LOG.debug("--------catch exception: {}", e.toString());
            throw new RuntimeException(e);
        }
        try {
            intercepter.getTestingService().setReceivingState(subnodeId);
        } catch (final RemoteException e) {
            LOG.debug("Encountered a remote exception", e);
            throw new RuntimeException(e);
        }
    }

    after(): runLearnerHandler() {
        final long threadId = Thread.currentThread().getId();
        final String threadName = Thread.currentThread().getName();
        LOG.debug("after runLearnerHandler-------Thread: {}, {}------", threadId, threadName);
        Long learnerHandlerThreadId = Thread.currentThread().getId();
        quorumPeerAspect.deregisterSubnode(learnerHandlerThreadId);
//        assert learnerHandlerSenderMap.containsKey(learnerHandlerThreadId);
        Long learnerHandlerSenderThreadId = learnerHandlerSenderThreadMap.get(learnerHandlerThreadId); // may be null in discovery phase
        if (learnerHandlerThreadId != null) {
            quorumPeerAspect.deregisterSubnode(learnerHandlerSenderThreadId);
            LOG.debug("de-registered: learnerHandlerThreadId: {} - learnerHandlerSenderThreadId: {}",
                    learnerHandlerThreadId, learnerHandlerSenderThreadId);
            learnerHandlerSenderThreadMap.remove(learnerHandlerThreadId);
            learnerHandlerThreadMap.remove(learnerHandlerSenderThreadId);
        }
    }


    // intercept the sender thread created by a learner handler

    pointcut runLearnerHandlerSender(java.lang.Thread childThread):
            withincode(* org.apache.zookeeper.server.quorum.LearnerHandler.run())
                && call(* java.lang.Thread.start())
                && target(childThread);

    before(java.lang.Thread childThread): runLearnerHandlerSender(childThread) {
        final long threadId = Thread.currentThread().getId();
        final String threadName = Thread.currentThread().getName();
        final long childThreadId = childThread.getId();
        final String childThreadName = childThread.getName();
        LOG.debug("before runSender-------parent thread {}: {}------", threadId, threadName);
        LOG.debug("before runSender-------child Thread {}: {}------", childThreadId, childThreadName);
        quorumPeerAspect.registerSubnode(childThreadId, childThreadName, SubnodeType.LEARNER_HANDLER_SENDER);
        learnerHandlerSenderThreadMap.put(threadId, childThreadId);
        learnerHandlerThreadMap.put(childThreadId, threadId);
    }

//    after(java.lang.Thread childThread): runLearnerHandlerSender(childThread) {
//        final long threadId = Thread.currentThread().getId();
//        final String threadName = Thread.currentThread().getName();
//        final long childThreadId = childThread.getId();
//        final String childThreadName = childThread.getName();
//        LOG.debug("after runSender-------parent thread: {}, {}------", threadId, threadName);
//        LOG.debug("after runSender-------child Thread: {}, {}------", childThreadId, childThreadName);
//        quorumPeerAspect.deregisterSubnode(childThreadId);
//    }


//    pointcut closeSock():
//            within(org.apache.zookeeper.server.quorum.LearnerHandler) && call(* java.net.Socket.close());
//
//    after(): closeSock() {
//        final long threadId = Thread.currentThread().getId();
//        final String threadName = Thread.currentThread().getName();
//        LOG.debug("after closeSock-------Thread: {}, {}------", threadId, threadName);
//        quorumPeerAspect.deregisterSubnode(threadId);
//    }


    /***
     * For LearnerHandlerSender
     * Set RECEIVING state when the queue is empty
     */
    pointcut takeOrPollFromQueue(LinkedBlockingQueue queue):
            within(org.apache.zookeeper.server.quorum.LearnerHandler)
                    && (call(* LinkedBlockingQueue.poll()) || call(* LinkedBlockingQueue.take()))
                    && target(queue);

    before(final LinkedBlockingQueue queue): takeOrPollFromQueue(queue) {
        final long threadId = Thread.currentThread().getId();
        final String threadName = Thread.currentThread().getName();
        LOG.debug("before advice of learner handler send-------Thread: {}, {}------", threadId, threadName);

        QuorumPeerAspect.SubnodeIntercepter intercepter = quorumPeerAspect.getIntercepter(threadId);
        int subnodeId;
        try{
            subnodeId = intercepter.getSubnodeId();
        } catch (RuntimeException e) {
            LOG.debug("--------catch exception: {}", e.toString());
            throw new RuntimeException(e);
        }
        if (subnodeId == TestingDef.RetCode.NODE_CRASH) {
            LOG.debug("LearnerHandlerSender threadId: {}, subnodeId == -1, indicating the node is STOPPING or OFFLINE", threadId);
            return;
        }
        LOG.debug("--------------My queuedPackets has {} element.",
                queue.size());

        if (queue.isEmpty()) {
            // Going to block here. Better notify the scheduler
            LOG.debug("--------------Checked empty! My queuedPackets has {} element. Set subnode {} to RECEIVING state." +
                    " Will be blocked until some packet enqueues", queue.size(), subnodeId);
            try {
                intercepter.getTestingService().setReceivingState(subnodeId);
            } catch (final RemoteException e) {
                LOG.debug("Encountered a remote exception", e);
                throw new RuntimeException(e);
            }
        }
    }


    /***
     * For LearnerHandlerSender sending messages to followers during SYNC & BROADCAST phase
     *  --> LeaderSyncFollower: send DIFF / TRUNC / SNAP (intercepted in LearnerHandler) & NEWLEADER
     *  --> LeaderProcessACKLD: send UPTODATE
     *  --> leader send PROPOSAL & COMMIT in SYNC phase
     * For BROADCAST phase
     *  --> LeaderProcessRequest: send PROPOSAL to quorum followers
     *  --> LeaderProcessACK : send COMMIT after receiving quorum's logRequest (PROPOSAL) ACKs
     */
    pointcut writeRecord(Record r, String s):
            within(org.apache.zookeeper.server.quorum.LearnerHandler) && !withincode(void java.lang.Runnable.run()) &&
            call(* org.apache.jute.BinaryOutputArchive.writeRecord(Record, String)) && args(r, s);

    void around(Record r, String s): writeRecord(r, s) {
        LOG.debug("------around-before writeRecord");
        final long threadId = Thread.currentThread().getId();
        final String threadName = Thread.currentThread().getName();
        LOG.debug("before advice of learner handler sender-------Thread: {}, {}------", threadId, threadName);

        QuorumPeerAspect.SubnodeIntercepter intercepter = quorumPeerAspect.getIntercepter(threadId);
        int subnodeId;
        try{
            subnodeId = intercepter.getSubnodeId();
        } catch (RuntimeException e) {
            LOG.debug("--------catch exception: {}", e.toString());
            throw new RuntimeException(e);
        }
        if (subnodeId == TestingDef.RetCode.NODE_CRASH) {
            LOG.debug("LearnerHandlerSender threadId: {}, subnodeId == -1, indicating the node is STOPPING or OFFLINE", threadId);
            return;
        }
        QuorumPacket packet = (QuorumPacket) r;
        final String payload = quorumPeerAspect.packetToString(packet);
        final int type =  packet.getType();
        LOG.debug("---------Taking the packet ({}) from queued packets. Subnode: {}",
                            payload, subnodeId);


        try {
            // before offerMessage: increase sendingSubnodeNum
            if (type != Leader.PING) {
                quorumPeerAspect.setSubnodeSending(intercepter);
            }
//            quorumPeerAspect.setSubnodeSending(intercepter);

            final String receivingAddr = threadName.split("-")[1];
            final long zxid = packet.getZxid();
            final int lastPacketId = intercepter.getTestingService()
                    .offerLeaderToFollowerMessage(subnodeId, receivingAddr, zxid, payload, type);
            LOG.debug("lastPacketId = {}", lastPacketId);

            // to check if the node is crashed
            // after offerMessage: decrease sendingSubnodeNum and shutdown this node if sendingSubnodeNum == 0
            if (type != Leader.PING) {
                quorumPeerAspect.postSend(intercepter, subnodeId, lastPacketId);
            }
//            quorumPeerAspect.postSend(intercepter, subnodeId, lastPacketId);

////            // TODO: confirm this check before partition check is ok by checking the code of LearnerHandler
//            if (type == Leader.UPTODATE) {
//                quorumPeerAspect.getTestingService().readyForBroadcast(subnodeId);
//            }

            // Trick: set RECEIVING state here
            intercepter.getTestingService().setReceivingState(subnodeId);

            // to check if the partition happens
            if (lastPacketId == TestingDef.RetCode.NODE_PAIR_IN_PARTITION){
                // just drop the message
                LOG.debug("partition occurs! just drop the message.");

//                long learnerHandlerThreadId = learnerHandlerThreadMap.get(threadId);
//                LOG.debug("try to interrupt my learnerHandlerThread: {}", learnerHandlerThreadId);
//                ThreadGroup group = Thread.currentThread().getThreadGroup();
//                if (group != null) {
//                    Thread[] threads = new Thread[(int)(group.activeCount() * 1.2)];
//                    int count = group.enumerate(threads, true);
//                    for (int i = 0; i < count; i++) {
//                        LOG.debug("get thread: {}, {}", threads[i].getName(), threads[i].getId());
//                        if (learnerHandlerThreadId == threads[i].getId()) {
//                            Thread learnerHandlerThreadObject = threads[i];
//                            LOG.debug("learnerHandlerThreadObject: {}, {}", learnerHandlerThreadObject.getName(), learnerHandlerThreadObject.getId());
//                            learnerHandlerThreadObject.interrupt();
//                            LOG.debug("after interrupt my learnerHandlerThread: {}", learnerHandlerThreadId);
//                            break;
//                        }
//                    }
//                }

                throw new IOException();
//                return;
            }

            proceed(r, s);
        } catch (RemoteException e) {
            LOG.debug("Encountered a remote exception", e);
            throw new RuntimeException(e);
        } catch (IOException e) {
            LOG.debug("Encountered an IO exception", e);
            throw new RuntimeException(e);
        }

    }



    /***
     * For LearnerHandler reading record during DISCOVERY & SYNC
     * Related code: LearnerHandler.java
     */
    pointcut learnerHandlerReadRecord(Record r, String s):
            withincode(* org.apache.zookeeper.server.quorum.LearnerHandler.run()) &&
                    call(* org.apache.jute.BinaryInputArchive.readRecord(Record, String)) && args(r, s);

    before(Record r, String s): learnerHandlerReadRecord(r, s) {
        LOG.debug("------before learnerHandlerReadRecord");
        final long threadId = Thread.currentThread().getId();
        final String threadName = Thread.currentThread().getName();
        LOG.debug("before advice of learnerHandlerReadRecord-------Thread: {}, {}------", threadId, threadName);

        QuorumPeerAspect.SubnodeIntercepter intercepter = quorumPeerAspect.getIntercepter(threadId);
        int subnodeId;
        try{
            subnodeId = intercepter.getSubnodeId();
        } catch (RuntimeException e) {
            LOG.debug("--------catch exception: {}", e.toString());
            throw new RuntimeException(e);
        }
        if (subnodeId == TestingDef.RetCode.NODE_CRASH) {
            LOG.debug("LearnerHandler threadId: {}, subnodeId == -1, indicating the node is STOPPING or OFFLINE", threadId);
            return;
        }


        try {
            // before offerMessage: increase sendingSubnodeNum
            quorumPeerAspect.setSubnodeSending(intercepter);

            final String receivingAddr = threadName.split("-")[1];
            final int lastPacketId = intercepter.getTestingService().offerLeaderToFollowerMessage(
                    subnodeId, receivingAddr, -1L, null, TestingDef.MessageType.learnerHandlerReadRecord);
            LOG.debug("learnerHandlerReadRecord lastPacketId = {}", lastPacketId);

            quorumPeerAspect.postSend(intercepter, subnodeId, lastPacketId);

            // Trick: set RECEIVING state here
            intercepter.getTestingService().setReceivingState(subnodeId);

            // to check if the partition happens
            if (lastPacketId == TestingDef.RetCode.NODE_PAIR_IN_PARTITION){
                // just drop the message
                LOG.debug("partition occurs! just drop the message.");
                throw new SocketTimeoutException();
//                return;
            }
        } catch (RemoteException | SocketTimeoutException e) {
            LOG.debug("Encountered a remote exception", e);
            throw new RuntimeException(e);
        }
    }

//    after(Record r, String s) returning: learnerHandlerReadRecord(r, s) {
//        LOG.debug("------after learnerHandlerReadRecord");
//        final long threadId = Thread.currentThread().getId();
//        final String threadName = Thread.currentThread().getName();
//        LOG.debug("after advice of learner handler read-------Thread: {}, {}------", threadId, threadName);
//
//        QuorumPeerAspect.SubnodeIntercepter intercepter = quorumPeerAspect.getIntercepter(threadId);
//        int subnodeId;
//        try{
//            subnodeId = intercepter.getSubnodeId();
//        } catch (RuntimeException e) {
//            LOG.debug("--------catch exception: {}", e.toString());
//            throw new RuntimeException(e);
//        }
//        if (subnodeId == TestingDef.RetCode.NODE_CRASH) {
//            LOG.debug("LearnerHandler threadId: {}, subnodeId == -1, indicating the node is STOPPING or OFFLINE", threadId);
//            return;
//        }
//        QuorumPacket packet = (QuorumPacket) r;
//        final String payload = quorumPeerAspect.packetToString(packet);
//        final int type =  packet.getType();
//        LOG.debug("---------learnerHandler reading the packet ({}). Subnode: {}",
//                payload, subnodeId);
//
//        if (type != Leader.ACKEPOCH) {
//            return;
//        }
//
//        try {
//            final String receivingAddr = threadName.split("-")[1];
//            final long zxid = packet.getZxid();
//            final int lastPacketId = intercepter.getTestingService()
//                    .offerLeaderToFollowerMessage(subnodeId, receivingAddr, zxid, payload, type);
//            // Trick: set RECEIVING state here
//            intercepter.getTestingService().setReceivingState(subnodeId);
//        } catch (RemoteException e) {
//            LOG.debug("Encountered a remote exception", e);
//            throw new RuntimeException(e);
//        }
//    }

    /***
     * For LearnerHandler sending followers' message during SYNC phase immediately without adding to the queue
     * package type:
     * (for ZAB1.0) LEADERINFO (17)
     * (for ZAB < 1.0) NEWLEADER (10)
     * (for ZAB1.0) DIFF (13) / TRUNC (14) / SNAP (15)
     *  --> only for intercepting LeaderSyncFollower in ZAB1.0 :
     *          send DIFF / TRUNC / SNAP (intercepted in LearnerHandler)
     *              & NEWLEADER (intercepted in LearnerHandlerSender)
     */
    pointcut learnerHandlerWriteRecord(Record r, String s):
            withincode(* org.apache.zookeeper.server.quorum.LearnerHandler.run()) &&
                    call(* org.apache.jute.BinaryOutputArchive.writeRecord(Record, String)) && args(r, s);

    void around(Record r, String s): learnerHandlerWriteRecord(r, s) {
        LOG.debug("------around-before learnerHandlerWriteRecord");
        final long threadId = Thread.currentThread().getId();
        final String threadName = Thread.currentThread().getName();
        LOG.debug("before advice of learner handler-------Thread: {}, {}------", threadId, threadName);

        QuorumPeerAspect.SubnodeIntercepter intercepter = quorumPeerAspect.getIntercepter(threadId);
        int subnodeId = -1;
        try{
            subnodeId = intercepter.getSubnodeId();
        } catch (RuntimeException e) {
            LOG.debug("--------catch exception in learnerHandlerWriteRecord: {}", e.toString());
            throw new RuntimeException(e);
        }
        if (subnodeId == TestingDef.RetCode.NODE_CRASH) {
            LOG.debug("LearnerHandler threadId: {}, subnodeId == -1, indicating the node is STOPPING or OFFLINE", threadId);
            return;
        }
        // Intercept QuorumPacket
        QuorumPacket packet = (QuorumPacket) r;
        final String payload = quorumPeerAspect.packetToString(packet);

        final int type =  packet.getType();
        LOG.debug("--------------I am a LearnerHandler. QuorumPacket {}. Set subnode {} to RECEIVING state. Type: {}",
                payload, subnodeId, type);

//        // TODO: this filter can be moved to the server side
//        switch (type) {
//            case Leader.DIFF:
//            case Leader.TRUNC:
//            case Leader.SNAP:
//                break;
//            default:
//                proceed(r, s);
//                return;
//        }

        try {

            // before offerMessage: increase sendingSubnodeNum
            quorumPeerAspect.setSubnodeSending(intercepter);

            final String receivingAddr = threadName.split("-")[1];
            final long zxid = packet.getZxid();
            final int lastPacketId = intercepter.getTestingService()
                    .offerLeaderToFollowerMessage(subnodeId, receivingAddr, zxid, payload, type);
            LOG.debug("learnerHandlerWriteRecord lastPacketId = {}", lastPacketId);

            quorumPeerAspect.postSend(intercepter, subnodeId, lastPacketId);

            // Trick: set RECEIVING state here
            intercepter.getTestingService().setReceivingState(subnodeId);

            // to check if the partition happens
            if (lastPacketId == TestingDef.RetCode.NODE_PAIR_IN_PARTITION){
                // just drop the message
                LOG.debug("partition occurs! just drop the message.");
                throw new SocketTimeoutException();
//                return;
            }

            proceed(r, s);
        } catch (RemoteException | SocketTimeoutException e ) {
            LOG.debug("Encountered a remote exception", e);
            throw new RuntimeException(e);
        }
    }

//    /***
//     * intercept learnerHandler's readPacket from follower
//     *
//     */
//    pointcut learnerHandlerWriteRecord(Record r, String s):
//            withincode(* org.apache.zookeeper.server.quorum.LearnerHandler.run()) &&
//                    call(* org.apache.jute.BinaryOutputArchive.writeRecord(Record, String)) && args(r, s);


//    /***
//     * intercept learnerHandler calling leader's waitForEpochAck method
//     */
//    pointcut waitForEpochAck(long id):
//            withincode(* org.apache.zookeeper.server.quorum.LearnerHandler.run()) &&
//                    call(* org.apache.zookeeper.server.quorum.Leader.waitForEpochAck(long, *)) && args(id, *);
//
//    before(long id): waitForEpochAck(id) {
//        LOG.debug("before waitForEpochAck, sid: {}", id);
//        final long threadId = Thread.currentThread().getId();
//        final String threadName = Thread.currentThread().getName();
//        LOG.debug("before advice of waitForEpochAck-------Thread: {}, {}------", threadId, threadName);
//
//        QuorumPeerAspect.SubnodeIntercepter intercepter = quorumPeerAspect.getIntercepter(threadId);
//        int subnodeId = -1;
//        try{
//            subnodeId = intercepter.getSubnodeId();
//        } catch (RuntimeException e) {
//            LOG.debug("--------catch exception in waitForEpochAck: {}", e.toString());
//            throw new RuntimeException(e);
//        }
//        if (subnodeId == TestingDef.RetCode.NODE_CRASH) {
//            LOG.debug("LearnerHandler threadId: {}, subnodeId == -1, indicating the node is STOPPING or OFFLINE", threadId);
//            return;
//        }
//
//        try {
//
//            // before offerMessage: increase sendingSubnodeNum
//            quorumPeerAspect.setSubnodeSending(intercepter);
//            final int lastPacketId = intercepter.getTestingService()
//                    .offerLocalEvent(subnodeId, SubnodeType.LEARNER_HANDLER, id, null, TestingDef.LocalEventType.waitForEpochAck);
//            LOG.debug("waitForEpochAck lastPacketId = {}", lastPacketId);
//            quorumPeerAspect.postSend(intercepter, subnodeId, lastPacketId);
//            // Trick: set RECEIVING state here
//            intercepter.getTestingService().setReceivingState(subnodeId);
//        } catch (RemoteException e) {
//            LOG.debug("Encountered a remote exception", e);
//            throw new RuntimeException(e);
//        }
//    }

}
