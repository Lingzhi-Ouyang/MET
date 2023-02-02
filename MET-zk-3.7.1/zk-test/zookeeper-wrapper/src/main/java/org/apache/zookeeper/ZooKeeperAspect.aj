package org.apache.zookeeper;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public aspect ZooKeeperAspect {

    private static final Logger LOG = LoggerFactory.getLogger(ZooKeeperAspect.class);

//    private final TestingRemoteService testingService;
//
//    public ZooKeeperAspect() {
//        try {
//            final Registry registry = LocateRegistry.getRegistry(2599);
//            testingService = (TestingRemoteService) registry.lookup(TestingRemoteService.REMOTE_NAME);
//            LOG.debug("Found the remote testing service.");
//        } catch (final RemoteException e) {
//            LOG.error("Couldn't locate the RMI registry.", e);
//            throw new RuntimeException(e);
//        } catch (final NotBoundException e) {
//            LOG.error("Couldn't bind the testing service.", e);
//            throw new RuntimeException(e);
//        }
//    }
//
//    public TestingRemoteService getTestingService() {
//        return testingService;
//    }
//
//    // Intercept ZooKeeper.getChildren()
//
////    pointcut getChildren(String p, boolean w): call(* ZooKeeper.getChildren(String, boolean))
////            && args(p, w);
////
////    before(String p, boolean w): getChildren(p, w) {
////        LOG.debug("Getting children of " + p);
////    }
//
//    pointcut getChildren(): call(* ZooKeeper.getChildren(..));
//
//    before(): getChildren() {
//        LOG.debug("Getting children ");
//    }
//
////    after(String p, boolean w) returning: getChildren(p, w) {
////        LOG.debug("Getting children of " + p);
////    }


}
