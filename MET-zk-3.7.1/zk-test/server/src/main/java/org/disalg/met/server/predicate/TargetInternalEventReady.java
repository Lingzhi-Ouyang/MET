package org.disalg.met.server.predicate;

import org.disalg.met.api.ModelAction;
import org.disalg.met.api.NodeState;
import org.disalg.met.api.configuration.SchedulerConfigurationException;
import org.disalg.met.server.TestingService;
import org.disalg.met.server.event.Event;
import org.disalg.met.server.event.LocalEvent;
import org.disalg.met.server.scheduler.ExternalModelStrategy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Set;

public class TargetInternalEventReady implements WaitPredicate{
    private static final Logger LOG = LoggerFactory.getLogger(TargetInternalEventReady.class);

    private final TestingService testingService;

    private final ExternalModelStrategy externalModelStrategy;

    private final ModelAction modelAction;

    private final Integer nodeId;

    private final Integer peerId;

    private Event event = null;

    private long modelZxid;

    public TargetInternalEventReady(final TestingService testingService,
                                    ExternalModelStrategy strategy,
                                    ModelAction action,
                                    Integer nodeId,
                                    Integer peerId,
                                    long modelZxid) {
        this.testingService = testingService;
        this.externalModelStrategy = strategy;
        this.modelAction = action;
        this.nodeId = nodeId;
        this.peerId = peerId;
        this.modelZxid = modelZxid;
    }

    public Event getEvent() {
        return event;
    }

    @Override
    public boolean isTrue() {
        try {
            event = externalModelStrategy.getNextInternalEvent(modelAction, nodeId, peerId, modelZxid);
        } catch (SchedulerConfigurationException e) {
            LOG.debug("SchedulerConfigurationException found when scheduling {}!", modelAction);
            return false;
        }
        return event != null;
    }

    @Override
    public String describe() {
        if (event instanceof LocalEvent) {
            return "target local event (action: " + modelAction +
                    " node: " + nodeId +
                    " ready";
        } else {
            return "target message event (action: " + modelAction +
                    " sendingNode: " + peerId +
                    " receivingNode: " + nodeId +
                    " ready";
        }
    }
}
