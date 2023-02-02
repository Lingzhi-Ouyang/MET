package org.apache.zookeeper.server.quorum;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public aspect QuorumCnxManagerAspect {

    private static final Logger LOG = LoggerFactory.getLogger(QuorumCnxManagerAspect.class);

    // Intercept operating on the recvQueue within QuorumCnxManager.addToRecvQueue

    pointcut addToRecvQueue():
            withincode(* QuorumCnxManager.addToRecvQueue(..))
            && call(* java.util.concurrent.ArrayBlockingQueue.add(..));

    after() returning: addToRecvQueue() {
        final WorkerReceiverAspect workerReceiverAspect = WorkerReceiverAspect.aspectOf();
        workerReceiverAspect.getMsgsInRecvQueue().incrementAndGet();
    }

    pointcut removeFromRecvQueue():
            withincode(* QuorumCnxManager.addToRecvQueue(..))
            && call(* java.util.concurrent.ArrayBlockingQueue.remove());

    after() returning: removeFromRecvQueue() {
        final WorkerReceiverAspect workerReceiverAspect = WorkerReceiverAspect.aspectOf();
        workerReceiverAspect.getMsgsInRecvQueue().decrementAndGet();
    }
}
