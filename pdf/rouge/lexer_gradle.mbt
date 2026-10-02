///|
/// Rouge's `Gradle.keywords`: Groovy's and Gradle's.
let gradle_keywords : Set[String] = groovy_keywords.union(
  word_set(
    (
      #|allprojects artifacts buildscript configuration dependencies
      #|repositories sourceSets subprojects publishing
    ),
  ),
)

///|
/// Rouge's `Gradle.types`: Groovy's and Gradle's.
let gradle_types : Set[String] = groovy_types.union(
  word_set(
    (
      #|Project Task Gradle Settings Script JavaToolChain SourceSet
      #|SourceSetOutput IncrementalTaskInputs Configuration
      #|ResolutionStrategy ArtifactResolutionQuery ComponentSelection
      #|ComponentSelectionRules ConventionProperty ExtensionAware
      #|ExtraPropertiesExtension PublishingExtension IvyPublication
      #|IvyArtifact IvyArtifactSet IvyModuleDescriptorSpec
      #|MavenPublication MavenArtifact MavenArtifactSet MavenPom
      #|PluginDependenciesSpec PluginDependencySpec ResourceHandler
      #|TextResourceFactory
    ),
  ),
)

///|
/// Rouge's `Gradle` (lexers/gradle.rb), a `Groovy` lexer.
pub fn gradle(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("gradle", options~)
  groovy_states(lx, gradle_keywords, gradle_types)
  lx
}
