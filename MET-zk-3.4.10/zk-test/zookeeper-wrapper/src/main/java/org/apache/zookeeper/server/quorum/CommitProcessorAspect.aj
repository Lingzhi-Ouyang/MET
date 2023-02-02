package org.apache.zookeeper.server.quorum;

import org.apache.zookeeper.ZooDefs;
import org.apache.zookeeper.server.Request;
import org.disalg.met.api.SubnodeType;
import org.disalg.met.api.TestingDef;
import org.disalg.met.api.TestingRemoteService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.rmi.RemoteException;
import java.util.ArrayList;

public aspect CommitProcessorAspect {
    private static final Logger LOG = LoggerFactory.getLogger(CommitProcessorAspect.class);

    private final QuorumPeerAspect quorumPeerAspect = QuorumPeerAspect.aspectOf();

    private TestingRemoteService testingService;

    private int subnodeId;

    // Intercept starting the CommitProcessor thread

    pointcut runCommitProcessor(): execution(* CommitProcessor.run());

    before(): runCommitProcessor() {
        LOG.debug("-------before runCommitProcessor. Thread {}: {}------",Thread.currentThread().getId(), Thread.currentThread().getName());
        testingService = quorumPeerAspect.createRmiConnection();
        subnodeId = quorumPeerAspect.registerSubnode(testingService, SubnodeType.COMMIT_PROCESSOR);
        try {
            testingService.setReceivingState(subnodeId);
        } catch (final RemoteException e) {
            LOG.debug("Encountered a remote exception", e);
            throw new RuntimeException(e);
        }

    }

    after(): runCommitProcessor() {
        LOG.debug("after runCommitProcessor");
        quorumPeerAspect.deregisterSubnode(testingService, subnodeId, SubnodeType.COMMIT_PROCESSOR);
    }

    /***
     *  intercept adding a request to the queue toProcess
     *  The target method is called in CommitProcessor's run()
     *   --> FollowerProcessCOMMIT
     */
    pointcut addToProcess(ArrayList queue, Object object):
            withincode(* org.apache.zookeeper.server.quorum.CommitProcessor.run())
                    && call(* ArrayList.add(java.lang.Object))
                    && if (object instanceof Request)
                    && target(queue) && args(object);

    before(ArrayList queue, Object object): addToProcess(queue, object) {
        final long threadId = Thread.currentThread().getId();
        final String threadName = Thread.currentThread().getName();
        LOG.debug("before advice of CommitProcessor.addToProcess()-------Thread: {}, {}------", threadId, threadName);
        final Request request = (Request) object;
        LOG.debug("--------------Before addToProcess {}: My toProcess has {} element. commitSubnode: {}",
                request, queue.size(), subnodeId);
        if (subnodeId == TestingDef.RetCode.NODE_CRASH) {
            LOG.debug("COMMIT threadId: {}, subnodeId == -1, indicating the node is STOPPING or OFFLINE", threadId);
            return;
        }
        final int type = request.type;
        switch (type) {
            case TestingDef.OpCode.create:
            case TestingDef.OpCode.delete:
            case TestingDef.OpCode.setData:
            case TestingDef.OpCode.multi:
            case TestingDef.OpCode.setACL:
            case TestingDef.OpCode.createSession:
            case TestingDef.OpCode.closeSession:
            case TestingDef.OpCode.error:
                LOG.debug("Will intercept toProcess request: {} ", request);
                break;
            default:
                LOG.debug("Won't intercept toProcess request: {} ", request);
                return;
        }
        try {
            // before offerMessage: increase sendingSubnodeNum
            quorumPeerAspect.setSubnodeSending();
            final String payload = quorumPeerAspect.constructRequest(request);
            final long zxid = request.zxid;
            final int lastCommitRequestId =
                    testingService.offerLocalEvent(subnodeId, SubnodeType.COMMIT_PROCESSOR, zxid, payload, type);
            LOG.debug("lastCommitRequestId = {}", lastCommitRequestId);
            // after offerMessage: decrease sendingSubnodeNum and shutdown this node if sendingSubnodeNum == 0
            quorumPeerAspect.postSend(subnodeId, lastCommitRequestId);
            // set RECEIVING state
            testingService.setReceivingState(subnodeId);
        } catch (final RemoteException e) {
            LOG.debug("Encountered a remote exception", e);
            throw new RuntimeException(e);
        }
    }

//    /***
//     *  possible issue: other threads may reach this pointcut before the CommitProcessor starts
//     *     // intercept getting the request from the queue committedRequests
//     *     // This method is called by
//     *     // For follower: QuorumPeer
//     *     // For leader: LearnerHandler / SyncRequestProcessor
//     */
//    pointcut commit(LinkedList queue, Request request):
//            withincode(void CommitProcessor.commit(Request))
//                && call(* LinkedList.add(..))
//                && target(queue) && args(request);
//
//    before(LinkedList queue, Request request): commit(queue, request) {
//        final long threadId = Thread.currentThread().getId();
//        final String threadName = Thread.currentThread().getName();
//        LOG.debug("before advice of CommitProcessor.commit()-------QuorumPeer Thread: {}, {}------", threadId, threadName);
////        QuorumPeerAspect.SubnodeIntercepter intercepter = quorumPeerAspect.getIntercepter(threadId);
//        LOG.debug("--------------Before adding commit request {}: My commitRequests has {} element. commitSubnode: {}",
//                request.type, queue.size(), subnodeId);
//        final int type =  request.type;
//        switch (type) {
//            case TestingDef.OpCode.notification:
//            case TestingDef.OpCode.create:
//            case TestingDef.OpCode.delete:
//            case TestingDef.OpCode.createSession:
//            case TestingDef.OpCode.exists:
//            case TestingDef.OpCode.check:
//            case TestingDef.OpCode.multi:
//            case TestingDef.OpCode.sync:
//            case TestingDef.OpCode.getACL:
//            case TestingDef.OpCode.setACL:
//            case TestingDef.OpCode.getChildren:
//            case TestingDef.OpCode.getChildren2:
//            case TestingDef.OpCode.ping:
//            case TestingDef.OpCode.closeSession:
//            case TestingDef.OpCode.setWatches:
//                LOG.debug("Won't intercept commit request: {} ", request);
//                return;
//            default:
//        }
//        try {
//            // before offerMessage: increase sendingSubnodeNum
//            quorumPeerAspect.setSubnodeSending();
//            final String payload = quorumPeerAspect.constructRequest(request);
//            LOG.debug("-----before getting this pointcut in the synchronized method: " + request);
////            int lastCommitRequestId = intercepter.getTestingService().commit(subnodeId, payload, type);
//            final int lastCommitRequestId =
//                    testingService.offerRequestProcessorMessage(subnodeId, SubnodeType.COMMIT_PROCESSOR, payload);
//            LOG.debug("lastCommitRequestId = {}", lastCommitRequestId);
//            // after offerMessage: decrease sendingSubnodeNum and shutdown this node if sendingSubnodeNum == 0
//            quorumPeerAspect.postSend(subnodeId, lastCommitRequestId);
//            // TODO: is there any better position to set receiving state?
////            intercepter.getTestingService().setReceivingState(subnodeId);
//            testingService.setReceivingState(subnodeId);
//        } catch (final RemoteException e) {
//            LOG.debug("Encountered a remote exception", e);
//            throw new RuntimeException(e);
//        }
//    }
}
