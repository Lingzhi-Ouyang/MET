package org.disalg.met.server.predicate;

import org.disalg.met.server.TestingService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class FollowerMappingLearnerHandlerSender implements WaitPredicate{
    private static final Logger LOG = LoggerFactory.getLogger(FollowerMappingLearnerHandlerSender.class);

    private final TestingService testingService;

    private final int subnodeId;

    public FollowerMappingLearnerHandlerSender(final TestingService testingService,
                                 final int subnodeId) {
        this.testingService = testingService;
        this.subnodeId = subnodeId;
    }

    @Override
    public boolean isTrue() {
        return testingService.getFollowerLearnerHandlerSenderMap(subnodeId) != null;
    }

    @Override
    public String describe() {
        return " follower " + subnodeId + "  mapping its learnerHandlerSender";
    }
}
