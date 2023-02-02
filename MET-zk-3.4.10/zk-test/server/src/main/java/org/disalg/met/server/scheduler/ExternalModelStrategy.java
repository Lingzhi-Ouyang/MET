package org.disalg.met.server.scheduler;

import com.alibaba.fastjson.JSONArray;
import com.alibaba.fastjson.JSONObject;
import org.disalg.met.api.*;
import org.disalg.met.api.configuration.SchedulerConfigurationException;
import org.disalg.met.server.TestingService;
import org.disalg.met.server.event.Event;
import org.disalg.met.server.event.FollowerToLeaderMessageEvent;
import org.disalg.met.server.event.LeaderToFollowerMessageEvent;
import org.disalg.met.server.event.LocalEvent;
import org.disalg.met.server.state.Subnode;
import org.disalg.met.server.statistics.ExternalModelStatistics;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.apache.commons.lang3.StringUtils;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class ExternalModelStrategy implements SchedulingStrategy{
    private static final Logger LOG = LoggerFactory.getLogger(ExternalModelStrategy.class);

    private final TestingService testingService;

    private final Random random;

    private File dir;
    private File[] files;
    private List<Trace> traces = new LinkedList<>();
    private int count = 0;
    private Trace currentTrace = null;

    private boolean nextEventPrepared = false;
    private Event nextEvent = null;
    private final Set<Event> events = new HashSet<>();

    private final ExternalModelStatistics statistics;

    public ExternalModelStrategy(TestingService testingService, Random random, File dir, final ExternalModelStatistics statistics) throws SchedulerConfigurationException {
        this.testingService = testingService;
        this.random = random;
        this.dir = dir;
        this.files = new File(String.valueOf(dir)).listFiles();
        assert files != null;
        this.statistics = statistics;
        load();
    }

    public int getTracesNum() {
        return count;
    }

    public Trace getCurrentTrace(final int idx) {
        assert idx < count;
        currentTrace = traces.get(idx);
        return currentTrace;
    }

    public Set<Event> getEvents() {
        return events;
    }

    public void clearEvents() {
        events.clear();
    }

    @Override
    public void add(final Event event) {
        LOG.debug("Adding event: {}", event.toString());
        events.add(event);
        if (nextEventPrepared && nextEvent == null) {
            nextEventPrepared = false;
        }
    }

    @Override
    public void remove(Event event) {
        LOG.debug("Removing event: {}", event.toString());
        events.remove(event);
        if (nextEventPrepared) {
            nextEventPrepared = false;
        }
    }

    @Override
    public boolean hasNextEvent() {
        if (!nextEventPrepared) {
            try {
                prepareNextEvent();
            } catch (SchedulerConfigurationException e) {
                LOG.error("Error while preparing next event from trace {}", currentTrace);
                e.printStackTrace();
            }
        }
        return nextEvent != null;
    }

    @Override
    public Event nextEvent() {
        if (!nextEventPrepared) {
            try {
                prepareNextEvent();
            } catch (SchedulerConfigurationException e) {
                LOG.error("Error while preparing next event from trace {}", currentTrace);
                e.printStackTrace();
                return null;
            }
        }
        nextEventPrepared = false;
        LOG.debug("nextEvent: {}", nextEvent.toString());
        return nextEvent;
    }

    private void prepareNextEvent() throws SchedulerConfigurationException {
        final List<Event> enabled = new ArrayList<>();
        LOG.debug("prepareNextEvent: events.size: {}", events.size());
        for (final Event event : events) {
            if (event.isEnabled()) {
                LOG.debug("enabled : {}", event.toString());
                enabled.add(event);
            }
        }
        statistics.reportNumberOfEnabledEvents(enabled.size());

        nextEvent = null;
        if (enabled.size() > 0) {
            final int i = random.nextInt(enabled.size());
            nextEvent = enabled.get(i);
            events.remove(nextEvent);
        }
        nextEventPrepared = true;
    }

    public void load() throws SchedulerConfigurationException {
        LOG.debug("Loading traces from files");
        try {
            for (File file : files) {
                if (file.isFile() && file.exists()) {
                    Trace trace = importTrace(file);
                    if (null == trace) continue;
                    traces.add(trace);
                    count++;
//                    LOG.debug("trace: {}", trace.toString());
                } else {
                    LOG.debug("file does not exists! ");
                }
            }
            assert count == traces.size();
        } catch (final IOException e) {
            LOG.error("Error while loading execution data from {}", dir);
            throw new SchedulerConfigurationException(e);
        }
    }

    public Trace importTrace(File file) throws IOException {
        String filename = file.getName();
        // Only json files will be parsed
        if(filename.startsWith(".") || !filename.endsWith(".json")) {
            return null;
        }
        LOG.debug("Importing trace from file {}", filename);

        // acquire file text
        InputStreamReader read = null;
        try {
            read = new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8);
        } catch (FileNotFoundException e) {
            e.printStackTrace();
        }
        assert read != null;
        BufferedReader bufferedReader = new BufferedReader(read);
        String lineTxt;
        StringBuffer sb = new StringBuffer();
        while ((lineTxt = bufferedReader.readLine()) != null) {
            sb.append(lineTxt);
        }
        read.close();

        // parse json & store to the EventSequence structure

        String fileTxt = sb.toString().replaceAll("\r\n", "");
        JSONArray jsonArray = new JSONArray();
        if (StringUtils.isNoneBlank(fileTxt)) {
            jsonArray = JSONArray.parseArray(fileTxt);
        }


        // get cluster info
        JSONObject serverInfo = (JSONObject) jsonArray.remove(0);
        int serverNum = (int) serverInfo.get("server_num");
        List<String> serverIds = (List<String>) serverInfo.get("server_id");
        // By default, the node mapping:
        // s0 : id = 2
        // s1 : id = 1
        // s2 : id = 0

        int eventCount = jsonArray.size();
        Trace trace = new Trace(filename, serverNum, serverIds, jsonArray);
        LOG.debug("serverNum: {}, serverId: {}, eventCount: {}, jsonArraySize: {}",
                serverNum, serverIds, eventCount, eventCount);

        Set<String> keys = new HashSet<>();
        List<String> events = new LinkedList<>();
        for (int i = 0; i < eventCount; i++) {
            JSONObject jsonObject = (JSONObject) jsonArray.get(i);
            String key = jsonObject.keySet().iterator().next();
            keys.add(key);
            events.add(key);
        }
        LOG.debug("keySize: {}", keys.size());
        LOG.debug("keys: {}", keys);
        LOG.debug("events: {}", events);

        return trace;
    }

    public Event getNextInternalEvent(ModelAction action, int nodeId, int peerId, long modelZxid) throws SchedulerConfigurationException {
        // 1. get all enabled events
        final List<Event> enabled = new ArrayList<>();
        LOG.debug("prepareNextEvent: events.size: {}", events.size());
        for (final Event event : events) {
            if (event.isEnabled()) {
                LOG.debug("enabled : {}", event.toString());
                enabled.add(event);
            }
        }

        statistics.reportNumberOfEnabledEvents(enabled.size());

        if (enabled.size() == 0) {
            throw new SchedulerConfigurationException();
        }
        nextEvent = null;
        // 2. search specific pre-condition event that should be lied in the sender
        switch (action) {
            case LeaderSyncFollower: // follower to release ACKEPOCH
            case LeaderProcessACKLD: // follower to release ACKLD
            case FollowerToLeaderACK: // follower to release ACK
                searchFollowerMessage(action, peerId, nodeId, modelZxid, enabled);
                break;
            case FollowerProcessLEADERINFO:
            case FollowerProcessSyncMessage: // leader to release DIFF / TRUNC / SNAP
            case FollowerProcessPROPOSALInSync: // leader to release PROPOSAL
            case FollowerProcessCOMMITInSync: // leader to release COMMIT
            case FollowerProcessNEWLEADER: // leader to release NEWLEADER
            case LearnerHandlerReadRecord:
            case FollowerProcessUPTODATE: // leader to release UPTODATE
            case LeaderToFollowerProposal: // leader to release PROPOSAL
            case LeaderToFollowerCOMMIT: // leader to release COMMIT
                searchLeaderMessage(action, peerId, nodeId, modelZxid, enabled);
                break;
            case LeaderLog:
            case FollowerLog:
            case LeaderCommit:
            case FollowerCommit:
                searchLocalMessage(action, nodeId, modelZxid, enabled);
                break;
        }

        if ( nextEvent != null){
            LOG.debug("next event exists! {}", nextEvent);
        } else {
            throw new SchedulerConfigurationException();
        }

        nextEventPrepared = false;
        return nextEvent;
    }

    public void searchLeaderMessage(final ModelAction action,
                                    final int leaderId,
                                    final int followerId,
                                    final long modelZxid,
                                    List<Event> enabled) {
        for (final Event e : enabled) {
            if (e instanceof LeaderToFollowerMessageEvent) {
                final LeaderToFollowerMessageEvent event = (LeaderToFollowerMessageEvent) e;
                final int receivingNodeId = event.getReceivingNodeId();
                final int sendingSubnodeId = event.getSendingSubnodeId();
                final Subnode sendingSubnode = testingService.getSubnodes().get(sendingSubnodeId);
                final int sendingNodeId = sendingSubnode.getNodeId();
                if (sendingNodeId != leaderId || receivingNodeId != followerId) continue;
                final int type = event.getType();
                switch (type) {
                    case MessageType.LEADERINFO:
                        if (!action.equals(ModelAction.FollowerProcessLEADERINFO)) continue;
                        break;
                    case MessageType.DIFF:
                    case MessageType.TRUNC:
                    case MessageType.SNAP:
                        if (!action.equals(ModelAction.FollowerProcessSyncMessage)) continue;
                        break;
                    case MessageType.PROPOSAL:
                        if (testingService.getNodePhases().get(followerId).equals(Phase.SYNC)) {
                            if (!action.equals(ModelAction.FollowerProcessPROPOSALInSync)) continue;
                        } else {
                            if (!action.equals(ModelAction.LeaderToFollowerProposal)) continue;
                            // check the equality between zxid mapping from model to code
                            if (modelZxid > 0) {
                                LOG.debug("LeaderToFollowerProposal, check getModelToCodeZxidMap: {}, {}, {}",
                                        Long.toHexString(modelZxid),
                                        Long.toHexString(testingService.getModelToCodeZxidMap().get(modelZxid)),
                                        Long.toHexString(event.getZxid()));
                                if (event.getZxid() != testingService.getModelToCodeZxidMap().get(modelZxid)) continue;
                            }
                        }
                        break;
                    case MessageType.COMMIT:
                        if (testingService.getNodePhases().get(followerId).equals(Phase.SYNC)) {
                            if (!action.equals(ModelAction.FollowerProcessCOMMITInSync)) continue;
                        } else {
                            if (!action.equals(ModelAction.LeaderToFollowerCOMMIT)) continue;
                            // check the equality between zxid mapping from model to code
                            if (modelZxid > 0) {
                                LOG.debug("LeaderToFollowerCOMMIT, check getModelToCodeZxidMap: {}, {}, {}",
                                        Long.toHexString(modelZxid),
                                        Long.toHexString(testingService.getModelToCodeZxidMap().get(modelZxid)),
                                        Long.toHexString(event.getZxid()));
                                if (event.getZxid() != testingService.getModelToCodeZxidMap().get(modelZxid)) continue;
                            }
                        }
                        break;
                    case MessageType.NEWLEADER:
                        if (!action.equals(ModelAction.FollowerProcessNEWLEADER)) continue;
                        break;
                    case MessageType.UPTODATE:
                        if (!action.equals(ModelAction.FollowerProcessUPTODATE)) continue;
                        break;
                    case TestingDef.MessageType.learnerHandlerReadRecord:
                        if (!action.equals(ModelAction.LearnerHandlerReadRecord)) continue;
                        break;
                    default:
                        continue;
                }
                nextEvent = event;
                events.remove(nextEvent);
                break;
            }
        }
    }

    public void searchFollowerMessage(final ModelAction action,
                                      final int followerId,
                                      final int leaderId,
                                      final long modelZxid,
                                      List<Event> enabled) {
        for (final Event e : enabled) {
            if (e instanceof FollowerToLeaderMessageEvent) {
                final FollowerToLeaderMessageEvent event = (FollowerToLeaderMessageEvent) e;
                final int receivingNodeId = event.getReceivingNodeId();
                final int sendingSubnodeId = event.getSendingSubnodeId();
                final Subnode sendingSubnode = testingService.getSubnodes().get(sendingSubnodeId);
                final int sendingNodeId = sendingSubnode.getNodeId();
                if (sendingNodeId != followerId || receivingNodeId != leaderId) continue;
                final int lastReadType = event.getType(); // Note: this describes leader's previous message type that this ACK replies to
                switch (lastReadType) {
                    case MessageType.LEADERINFO:
                        if (!action.equals(ModelAction.LeaderSyncFollower)) continue;
                        break;
                    case MessageType.NEWLEADER:
                        if (!action.equals(ModelAction.LeaderProcessACKLD)) continue;
                        break;
                    case MessageType.UPTODATE:
                        if (!action.equals(ModelAction.FollowerToLeaderACK)) continue;
                        break;
                    case MessageType.PROPOSAL: // as for ACK to PROPOSAL during SYNC, we regard it as a local event
                    case MessageType.PROPOSAL_IN_SYNC:
                        if (!action.equals(ModelAction.FollowerToLeaderACK) ) continue;
                        // check the equality between zxid mapping from model to code
                        if (modelZxid > 0) {
                            LOG.debug("FollowerToLeaderACK, check getModelToCodeZxidMap: {}, {}, {}",
                                    Long.toHexString(modelZxid),
                                    Long.toHexString(testingService.getModelToCodeZxidMap().get(modelZxid)),
                                    Long.toHexString(event.getZxid()));
                            if (event.getZxid() != testingService.getModelToCodeZxidMap().get(modelZxid)) continue;
                        }
                        break;
                    default:
                        continue;
                }
                nextEvent = event;
                events.remove(nextEvent);
                break;
            }
        }
    }

    public void searchLocalMessage(final ModelAction action,
                                   final int nodeId,
                                   final long modelZxid,
                                   List<Event> enabled) {
        for (final Event e : enabled) {
            if (e instanceof LocalEvent) {
                final LocalEvent event = (LocalEvent) e;
                final int eventNodeId = event.getNodeId();
                if (eventNodeId != nodeId) continue;
                final SubnodeType subnodeType = event.getSubnodeType();
                final int type = event.getType();
                switch (action) {
//                    case LeaderWaitForEpochAck:
//                        // TODO：ia.readRecord(ackEpochPacket, "packet");
//                        break;
                    case LeaderLog:
                        final long eventZxid = event.getZxid();
                        final int eventType = event.getType();
                        if (!subnodeType.equals(SubnodeType.SYNC_PROCESSOR)) continue;
                        // since leaderLog always come first, here record the zxid mapping from model to code
                        if (modelZxid > 0) {
                            testingService.getModelToCodeZxidMap().put(modelZxid, eventZxid);
                            LOG.debug("LeaderLog, check getModelToCodeZxidMap: {}, {}, {}",
                                    Long.toHexString(modelZxid),
                                    Long.toHexString(testingService.getModelToCodeZxidMap().get(modelZxid)),
                                    Long.toHexString(event.getZxid()));
                        }
                        break;
                    case FollowerLog:
                        if (!subnodeType.equals(SubnodeType.SYNC_PROCESSOR)) continue;
                        // check the equality between zxid mapping from model to code
                        if (modelZxid > 0) {
                            LOG.debug("FollowerLog, check getModelToCodeZxidMap: {}, {}, {}",
                                    Long.toHexString(modelZxid),
                                    Long.toHexString(testingService.getModelToCodeZxidMap().get(modelZxid)),
                                    Long.toHexString(event.getZxid()));
                            if (event.getZxid() != testingService.getModelToCodeZxidMap().get(modelZxid)) continue;
                        }
                        break;
                    case FollowerProcessPROPOSAL:  // DEPRECATED
                        if (!subnodeType.equals(SubnodeType.SYNC_PROCESSOR)) continue;
//                        if (type != MessageType.PROPOSAL) continue; // set_data type == 5 not proposal!
                        break;
//                    case FollowerProcessSyncMessage: // intercept readPacketInSyncWithLeader. no ACK. process DIFF / TRUNC / SNAP /
//                    case FollowerProcessCOMMITInSync: // intercept readPacketInSyncWithLeader. no ACK
//                    case FollowerProcessPROPOSALInSync: // intercept readPacketInSyncWithLeader. TODO: this will reply ACK later
//                        if (!subnodeType.equals(SubnodeType.QUORUM_PEER)) continue;
//                        break;
                    case LeaderCommit:
                    case FollowerCommit:
//                    case FollowerProcessCOMMIT: // DEPRECATED
                        if (!subnodeType.equals(SubnodeType.COMMIT_PROCESSOR)) continue;
                        // check the equality between zxid mapping from model to code
                        if (modelZxid > 0) {
                            LOG.debug("ProcessCOMMIT, check getModelToCodeZxidMap: {}, {}, {}",
                                    Long.toHexString(modelZxid),
                                    Long.toHexString(testingService.getModelToCodeZxidMap().get(modelZxid)),
                                    Long.toHexString(event.getZxid()));
                            if (event.getZxid() != testingService.getModelToCodeZxidMap().get(modelZxid)) continue;
                        }
                        break;
                    default:
                        continue;
                }
                nextEvent = event;
                events.remove(nextEvent);
                break;
            }
        }
    }
}
