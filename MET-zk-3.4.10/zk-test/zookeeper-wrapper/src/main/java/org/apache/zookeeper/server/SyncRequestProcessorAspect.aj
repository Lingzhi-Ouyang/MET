package org.apache.zookeeper.server;

import org.apache.zookeeper.server.quorum.QuorumPeerAspect;
import org.disalg.met.api.SubnodeType;
import org.disalg.met.api.TestingDef;
import org.disalg.met.api.TestingRemoteService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.rmi.RemoteException;
import java.util.concurrent.LinkedBlockingQueue;

public aspect SyncRequestProcessorAspect {

    private static final Logger LOG = LoggerFactory.getLogger(SyncRequestProcessorAspect.class);

    private final QuorumPeerAspect quorumPeerAspect = QuorumPeerAspect.aspectOf();

    private TestingRemoteService testingService;

    private int subnodeId;


    public TestingRemoteService getTestingService() {
        return testingService;
    }

    // Intercept starting the SyncRequestProcessor thread

    pointcut runSyncProcessor(): execution(* SyncRequestProcessor.run());

    before(): runSyncProcessor() {
        testingService = quorumPeerAspect.createRmiConnection();
        LOG.debug("-------Thread: {}------", Thread.currentThread().getName());
        LOG.debug("before runSyncProcessor");
        subnodeId = quorumPeerAspect.registerSubnode(testingService, SubnodeType.SYNC_PROCESSOR);
        quorumPeerAspect.setSyncSubnodeId(subnodeId);
    }

    after(): runSyncProcessor() {
        LOG.debug("after runSyncProcessor");
        quorumPeerAspect.setSyncSubnodeId(-1);
        quorumPeerAspect.deregisterSubnode(testingService, subnodeId, SubnodeType.SYNC_PROCESSOR);
    }


    // Intercept message processed within SyncRequestProcessor
    // candidate 1: processRequest() called by its previous processor
    // Use candidate 2: LinkedBlockingQueue.take() / poll()

    /***
     * Intercept polling the receive queue of the queuedRequests within SyncRequestProcessor
     *  --> FollowerProcessPROPOSAL
     */
    pointcut takeOrPollFromQueue(LinkedBlockingQueue queue):
            within(SyncRequestProcessor)
                    && (call(* LinkedBlockingQueue.take())
                    || call(* LinkedBlockingQueue.poll()))
                    && target(queue);

    before(final LinkedBlockingQueue queue): takeOrPollFromQueue(queue) {
        // TODO: Aspect of aspect
        final long threadId = Thread.currentThread().getId();
        final String threadName = Thread.currentThread().getName();
        LOG.debug("before advice of sync-------Thread: {}, {}------", threadId, threadName);

//        QuorumPeerAspect.SubnodeIntercepter intercepter = quorumPeerAspect.getIntercepter(threadId);
        LOG.debug("--------------My queuedRequests has {} element. syncProcessorSubnodeId: {}.",
                queue.size(), subnodeId);
        if (queue.isEmpty()) {
            // Going to block here. Better notify the scheduler
            LOG.debug("--------------Checked! My toSync queuedRequests has {} element. Go to RECEIVING state." +
                    " Will be blocked until some request enqueues when nothing to flush", queue.size());
            try {
//                intercepter.getTestingService().setReceivingState(subnodeId);
                testingService.setReceivingState(subnodeId);
            } catch (final RemoteException e) {
                LOG.debug("Encountered a remote exception", e);
                throw new RuntimeException(e);
            }
        }
    }

    after(final LinkedBlockingQueue queue) returning (final Object request): takeOrPollFromQueue(queue) {
        // TODO: Aspect of aspect
        final long threadId = Thread.currentThread().getId();
        final String threadName = Thread.currentThread().getName();
        LOG.debug("after advice of sync-------Thread: {}, {}------", threadId, threadName);

//        QuorumPeerAspect.SubnodeIntercepter intercepter = quorumPeerAspect.getIntercepter(threadId);

        LOG.debug("--------------My queuedRequests has {} element. syncProcessorSubnodeId: {}.",
                queue.size(), subnodeId);
        if (subnodeId == TestingDef.RetCode.NODE_CRASH) {
            LOG.debug("SYNC threadId: {}, subnodeId == -1, indicating the node is STOPPING or OFFLINE", threadId);
            return;
        }

        if (request == null){
            LOG.debug("------It's not a request! Using poll() and flush now");
            return;
        }
        if (request instanceof Request) {
//            this.request = (Request) request;
            LOG.debug("It's a request {}", request);
            final String payload = quorumPeerAspect.constructRequest((Request) request);
            final int type =  ((Request) request).type;
//            switch (type) {
//                case TestingDef.OpCode.notification:
//                case TestingDef.OpCode.create:
//                case TestingDef.OpCode.delete:
//                case TestingDef.OpCode.createSession:
//                case TestingDef.OpCode.exists:
//                case TestingDef.OpCode.check:
//                case TestingDef.OpCode.multi:
//                case TestingDef.OpCode.sync:
//                case TestingDef.OpCode.getACL:
//                case TestingDef.OpCode.setACL:
//                case TestingDef.OpCode.getChildren:
//                case TestingDef.OpCode.getChildren2:
//                case TestingDef.OpCode.ping:
//                case TestingDef.OpCode.closeSession:
//                case TestingDef.OpCode.setWatches:
//                    LOG.debug("Won't intercept log request: {} ", request);
//                    return;
//                default:
//            }
            try {
                // before offerMessage: increase sendingSubnodeNum
                quorumPeerAspect.setSubnodeSending();
//                int lastSyncRequestId = intercepter.getTestingService().logRequestMessage(subnodeId, payload, type);
                final long zxid = ((Request) request).zxid;
                final int lastSyncRequestId =
                        testingService.offerLocalEvent(subnodeId, SubnodeType.SYNC_PROCESSOR, zxid, payload, type);
                LOG.debug("lastSyncRequestId = {}", lastSyncRequestId);
                // after offerMessage: decrease sendingSubnodeNum and shutdown this node if sendingSubnodeNum == 0
                quorumPeerAspect.postSend(subnodeId, lastSyncRequestId);
            } catch (RemoteException e) {
                e.printStackTrace();
            }
        }
    }

}
