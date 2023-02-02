package org.disalg.met.api;

public enum ModelAction {
    // set init state
    SetInitState,

    // external events
    NodeCrash,
    NodeStart,
    PartitionStart,
    PartitionRecover,

    ClientGetData,

    // election & discovery
    ElectionAndDiscovery,

    // sync
    FollowerProcessLEADERINFO,
    LeaderSyncFollower,
    FollowerProcessSyncMessage,
    FollowerProcessPROPOSALInSync,
    FollowerProcessCOMMITInSync,
    FollowerProcessNEWLEADER, LearnerHandlerReadRecord,
    LeaderProcessACKLD,
    FollowerProcessUPTODATE,

    // broadcast with sub-actions
    LeaderProcessRequest, LeaderLog,
    LeaderProcessACK, FollowerToLeaderACK, LeaderCommit,
    FollowerProcessPROPOSAL, LeaderToFollowerProposal, FollowerLog,// follower here also needs to LogPROPOSAL
    FollowerProcessCOMMIT, LeaderToFollowerCOMMIT, FollowerCommit// follower here also needs to ProcessCOMMIT

}
