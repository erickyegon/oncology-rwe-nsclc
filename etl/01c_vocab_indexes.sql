CREATE INDEX idx_concept_code ON cdm.concept (vocabulary_id, concept_code);
CREATE INDEX idx_concept_vocab ON cdm.concept (vocabulary_id);
CREATE INDEX idx_concept_domain ON cdm.concept (domain_id);
CREATE INDEX idx_cr_1 ON cdm.concept_relationship (concept_id_1);
CREATE INDEX idx_cr_2 ON cdm.concept_relationship (concept_id_2);
CREATE INDEX idx_ca_anc ON cdm.concept_ancestor (ancestor_concept_id);
CREATE INDEX idx_ca_desc ON cdm.concept_ancestor (descendant_concept_id);
CREATE INDEX idx_cs ON cdm.concept_synonym (concept_id);
ANALYZE;
